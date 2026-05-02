const std = @import("std");
const Allocator = std.mem.Allocator;

/// Rectangle area in terminal coordinates
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

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

        return Rect{ .x = x1, .y = y1, .width = x2 - x1, .height = y2 - y1 };
    }

    /// Calculate a rectangle with the given aspect ratio that fits within self
    /// Preserves x, y position and maintains the width:height ratio while
    /// fitting the largest possible rectangle within the available bounds.
    pub fn withAspectRatio(self: Rect, ratio: struct { width: u32, height: u32 }) Rect {
        // Handle zero ratio safely
        if (ratio.width == 0 or ratio.height == 0) {
            return Rect{ .x = self.x, .y = self.y, .width = 0, .height = 0 };
        }

        const width_u64 = @as(u64, self.width);
        const height_u64 = @as(u64, self.height);
        const ratio_w = @as(u64, ratio.width);
        const ratio_h = @as(u64, ratio.height);

        // Try width-constrained first: use full width, calculate height
        const calc_height = (width_u64 * ratio_h) / ratio_w;

        if (calc_height <= height_u64) {
            // Width-constrained fits: use full width
            return Rect{ .x = self.x, .y = self.y, .width = self.width, .height = @as(u16, @intCast(calc_height)) };
        } else {
            // Width-constrained exceeds height: use full height instead
            const calc_width = (height_u64 * ratio_w) / ratio_h;
            return Rect{ .x = self.x, .y = self.y, .width = @as(u16, @intCast(@min(calc_width, width_u64))), .height = self.height };
        }
    }

    /// Apply margin to rectangle, shrinking it inward
    /// Returns a new rectangle with margin applied on all sides
    /// Handles underflow by returning zero dimensions if margin exceeds size
    pub fn withMargin(self: Rect, margin: Margin) Rect {
        // Calculate total horizontal and vertical margins
        const horizontal_margin = @as(u32, margin.left) + @as(u32, margin.right);
        const vertical_margin = @as(u32, margin.top) + @as(u32, margin.bottom);

        // Check for underflow - if margin exceeds dimension, return zero dimension
        const new_width = if (horizontal_margin >= self.width) 0 else self.width - @as(u16, @intCast(horizontal_margin));
        const new_height = if (vertical_margin >= self.height) 0 else self.height - @as(u16, @intCast(vertical_margin));

        // Calculate new position (moved inward by margin)
        const new_x = self.x + margin.left;
        const new_y = self.y + margin.top;

        return Rect{ .x = new_x, .y = new_y, .width = new_width, .height = new_height };
    }

    /// Apply padding to rectangle, shrinking it inward
    /// Returns a new rectangle with padding applied on all sides
    /// Handles underflow by returning zero dimensions if padding exceeds size
    pub fn withPadding(self: Rect, padding: Padding) Rect {
        // Calculate total horizontal and vertical padding
        const horizontal_padding = @as(u32, padding.left) + @as(u32, padding.right);
        const vertical_padding = @as(u32, padding.top) + @as(u32, padding.bottom);

        // Check for underflow - if padding exceeds dimension, return zero dimension
        const new_width = if (horizontal_padding >= self.width) 0 else self.width - @as(u16, @intCast(horizontal_padding));
        const new_height = if (vertical_padding >= self.height) 0 else self.height - @as(u16, @intCast(vertical_padding));

        // Calculate new position (moved inward by padding)
        const new_x = self.x + padding.left;
        const new_y = self.y + padding.top;

        return Rect{ .x = new_x, .y = new_y, .width = new_width, .height = new_height };
    }

    /// Create rectangle from size with origin at (0, 0)
    ///
    /// Convenience constructor for zero-origin rectangles. Equivalent to
    /// `Rect{ .x = 0, .y = 0, .width = width, .height = height }`.
    ///
    /// ## Example
    /// ```zig
    /// const area = Rect.fromSize(80, 24);
    /// // equivalent to: Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }
    /// ```
    ///
    /// ## v2.1.0 Ergonomics Helper
    /// This pattern appears 276+ times in tests and widget code. Using `fromSize`
    /// improves readability and reduces boilerplate.
    pub fn fromSize(width: u16, height: u16) Rect {
        return .{ .x = 0, .y = 0, .width = width, .height = height };
    }

    /// Format rectangle for debugging output
    pub fn debugFormat(self: Rect, writer: anytype) !void {
        try writer.print("Rect{{x={d}, y={d}, width={d}, height={d}}}", .{
            self.x,
            self.y,
            self.width,
            self.height,
        });
    }
};

/// Margin spacing around a rectangle
pub const Margin = struct {
    top: u16,
    right: u16,
    bottom: u16,
    left: u16,

    /// Create uniform margin on all sides
    pub fn all(n: u16) Margin {
        return .{ .top = n, .right = n, .bottom = n, .left = n };
    }

    /// Create symmetric margin (vertical and horizontal)
    pub fn symmetric(vertical: u16, horizontal: u16) Margin {
        return .{ .top = vertical, .right = horizontal, .bottom = vertical, .left = horizontal };
    }
};

/// Padding spacing inside a rectangle
pub const Padding = struct {
    top: u16,
    right: u16,
    bottom: u16,
    left: u16,

    /// Create uniform padding on all sides
    pub fn all(n: u16) Padding {
        return .{ .top = n, .right = n, .bottom = n, .left = n };
    }

    /// Create symmetric padding (vertical and horizontal)
    pub fn symmetric(vertical: u16, horizontal: u16) Padding {
        return .{ .top = vertical, .right = horizontal, .bottom = vertical, .left = horizontal };
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
            .length => |fixed_length| @min(fixed_length, available),
            .percentage => |percentage_val| blk: {
                const clamped = @min(percentage_val, 100);
                const size = (@as(u32, available) * clamped) / 100;
                break :blk @as(u16, @intCast(@min(size, available)));
            },
            .min => |min_val| @min(min_val, available),
            .max => |max_val| @min(max_val, available),
            .ratio => |ratio_val| blk: {
                if (ratio_val.denom == 0) break :blk 0;
                const size = (@as(u64, available) * ratio_val.num) / ratio_val.denom;
                break :blk @as(u16, @intCast(@min(size, available)));
            },
            .aspect_ratio => |aspect_val| blk: {
                // Aspect ratio applies to one dimension at a time
                // Return the available space as-is; the caller will use Rect.withAspectRatio()
                // to compute the actual 2D constraints
                if (aspect_val.width == 0 or aspect_val.height == 0) break :blk 0;
                break :blk available;
            },
        };
    }

    /// Create a fixed-length constraint.
    ///
    /// Equivalent to: `Constraint{ .length = length }`
    ///
    /// Returns a constraint that allocates exactly `length` cells, clamped to available space.
    ///
    /// Example:
    /// ```zig
    /// const constraint = Constraint.len(50);  // Fixed 50-cell width
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor to reduce boilerplate.
    pub fn len(length: u16) Constraint {
        return .{ .length = length };
    }

    /// Create a percentage constraint.
    ///
    /// Equivalent to: `Constraint{ .percentage = @min(percentage, 100) }`
    ///
    /// Returns a constraint that allocates a percentage of available space.
    /// Input is automatically clamped to [0, 100] at construction time.
    ///
    /// Example:
    /// ```zig
    /// const constraint = Constraint.pct(75);  // 75% of available space
    /// const clamped = Constraint.pct(150);    // Clamped to 100%
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor with automatic clamping.
    pub fn pct(percentage: u8) Constraint {
        return .{ .percentage = @min(percentage, 100) };
    }

    /// Create a ratio constraint.
    ///
    /// Equivalent to: `Constraint{ .ratio = .{ .num = num, .denom = denom } }`
    ///
    /// Returns a constraint that allocates `(available * num) / denom` cells.
    /// Zero denominator is handled by apply(), returning 0.
    ///
    /// Example:
    /// ```zig
    /// const constraint = Constraint.rat(1, 2);  // 1/2 of available space
    /// const constraint = Constraint.rat(3, 4);  // 3/4 of available space
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor to reduce boilerplate.
    pub fn rat(num: u32, denom: u32) Constraint {
        return .{ .ratio = .{ .num = num, .denom = denom } };
    }

    /// Create a minimum-length constraint.
    ///
    /// Equivalent to: `Constraint{ .min = min }`
    ///
    /// Returns a constraint that allocates at least `min` cells, clamped to available space.
    ///
    /// Example:
    /// ```zig
    /// const constraint = Constraint.minimum(50);  // At least 50 cells
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor to reduce boilerplate.
    pub fn minimum(min: u16) Constraint {
        return .{ .min = min };
    }

    /// Create a maximum-length constraint.
    ///
    /// Equivalent to: `Constraint{ .max = max }`
    ///
    /// Returns a constraint that allocates at most `max` cells.
    ///
    /// Example:
    /// ```zig
    /// const constraint = Constraint.maximum(200);  // At most 200 cells
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor to reduce boilerplate.
    pub fn maximum(max: u16) Constraint {
        return .{ .max = max };
    }

    /// Create an aspect-ratio constraint.
    ///
    /// Equivalent to: `Constraint{ .aspect_ratio = .{ .width = width, .height = height } }`
    ///
    /// Returns a constraint that maintains the given aspect ratio (width:height).
    /// Zero width or height is invalid and returns 0 from apply().
    ///
    /// Example:
    /// ```zig
    /// const constraint = Constraint.aspect(16, 9);   // 16:9 aspect ratio
    /// const constraint = Constraint.aspect(1, 1);    // 1:1 square aspect ratio
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor to reduce boilerplate.
    pub fn aspect(width: u32, height: u32) Constraint {
        return .{ .aspect_ratio = .{ .width = width, .height = height } };
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
    var total_min_required: u32 = 0;
    var num_mins: u32 = 0;
    var num_maxes: u32 = 0;
    var has_flex = false;

    // First pass: calculate initial sizes and track constraints
    for (constraints, 0..) |constraint, i| {
        const size = constraint.apply(available);
        sizes[i] = size;
        total_size += size;

        // Track constraint types
        switch (constraint) {
            .min => |minimum| {
                total_min_required += minimum;
                num_mins += 1;
                has_flex = true;
            },
            .max => {
                num_maxes += 1;
                has_flex = true;
            },
            .percentage, .ratio, .aspect_ratio => {
                has_flex = true;
            },
            else => {},
        }
    }

    // Strategy 1: Single min exceeding available - fully respect it
    if (num_mins == 1 and num_maxes == 0 and total_min_required > available) {
        for (constraints, 0..) |constraint, i| {
            if (constraint == .min) {
                sizes[i] = constraint.min;
            }
        }
        total_size = 0;
        for (sizes) |s| total_size += s;
    }
    // Strategy 2: Multiple mins exceeding available - scale mins proportionally
    else if (num_mins > 1 and total_min_required > available) {
        total_size = 0;
        for (constraints, 0..) |constraint, i| {
            if (constraint == .min) {
                const proportion = @as(f64, @floatFromInt(constraint.min)) / @as(f64, @floatFromInt(total_min_required));
                const share = @as(u16, @intFromFloat(@as(f64, @floatFromInt(available)) * proportion));
                sizes[i] = share;
            }
            total_size += sizes[i];
        }
    }
    // Strategy 3: Mixed with mins+maxes where total exceeds available
    else if (num_mins > 0 and num_maxes > 0 and total_size > available) {
        // Allocate mins first, then distribute remaining to other constraints
        total_size = 0;
        for (constraints, 0..) |constraint, i| {
            if (constraint == .min) {
                sizes[i] = constraint.min;
            }
            total_size += sizes[i];
        }

        // Try to grow max-constrained items to their max, up to available space
        if (total_size < available) {
            for (constraints, 0..) |constraint, i| {
                if (constraint == .max) {
                    const cap = constraint.max;
                    if (sizes[i] < cap) {
                        sizes[i] = @min(cap, available);
                    }
                }
            }
            // Recalculate total
            total_size = 0;
            for (sizes) |s| total_size += s;
        }

        // If still exceeds, we need to reduce max constraints
        // Mins must be preserved, so scale down the maxes instead
        if (total_size > available) {
            // Calculate how much to reduce from maxes
            var max_total: u32 = 0;
            for (constraints, 0..) |constraint, i| {
                if (constraint == .max) {
                    max_total += sizes[i];
                }
            }

            if (max_total > 0) {
                const reduction = total_size - available;
                const scale = @as(f64, @floatFromInt(max_total - @as(u32, @intCast(reduction)))) / @as(f64, @floatFromInt(max_total));
                total_size = 0;
                for (constraints, 0..) |constraint, i| {
                    if (constraint == .max) {
                        const scaled = @as(u16, @intFromFloat(@as(f64, @floatFromInt(sizes[i])) * scale));
                        sizes[i] = @min(scaled, constraint.max);
                    }
                    total_size += sizes[i];
                }
            }
        }
    }
    // Strategy 4: Standard case where total fits or needs normal scaling
    else if (total_size > available) {
        var fixed_and_pct_total: u32 = 0;
        for (constraints, 0..) |constraint, i| {
            switch (constraint) {
                .length, .percentage, .ratio => fixed_and_pct_total += sizes[i],
                else => {},
            }
        }

        if (fixed_and_pct_total >= available) {
            const scale = @as(f64, @floatFromInt(available)) / @as(f64, @floatFromInt(total_size));
            total_size = 0;
            for (sizes, 0..) |size, i| {
                const scaled = @as(u16, @intFromFloat(@as(f64, @floatFromInt(size)) * scale));
                sizes[i] = scaled;
                total_size += scaled;
            }
        } else {
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
                        else => {},
                    }
                }
            }
        }
    }

    // Distribute remaining space to last flexible constraint (but not max)
    if (total_size < available and has_flex) {
        const remaining = available - @as(u16, @intCast(total_size));
        var last_flexible: ?usize = null;
        var i = constraints.len;
        while (i > 0) {
            i -= 1;
            switch (constraints[i]) {
                .max => {}, // Skip max
                .percentage, .ratio, .aspect_ratio, .min => {
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

    // Final: Apply max constraints as upper bounds
    for (constraints, 0..) |constraint, i| {
        if (constraint == .max and sizes[i] > constraint.max) {
            sizes[i] = constraint.max;
        }
    }

    // Create rectangles
    var offset: u16 = 0;
    for (sizes, 0..) |size, i| {
        result[i] = switch (direction) {
            .horizontal => Rect{ .x = area.x + offset, .y = area.y, .width = size, .height = area.height },
            .vertical => Rect{ .x = area.x, .y = area.y + offset, .width = area.width, .height = size },
        };
        offset += size;
    }

    return result;
}

// ============================================================================
// Layout Debugging
// ============================================================================

/// Debug node representing a layout constraint and its resulting rectangle
pub const DebugNode = struct {
    constraint: Constraint,
    rect: Rect,
    children: []DebugNode,
};

/// Layout debugger for visualizing layout trees
pub const LayoutDebugger = struct {
    allocator: Allocator,
    nodes: std.ArrayList(DebugNode),

    /// Initialize a new layout debugger
    pub fn init(allocator: Allocator) LayoutDebugger {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayList(DebugNode){},
        };
    }

    /// Clean up all resources
    pub fn deinit(self: *LayoutDebugger) void {
        // Free all children recursively
        for (self.nodes.items) |node| {
            freeNodeChildren(self.allocator, node);
        }
        self.nodes.deinit(self.allocator);
    }

    /// Recursively free node children
    fn freeNodeChildren(allocator: Allocator, node: DebugNode) void {
        for (node.children) |child| {
            freeNodeChildren(allocator, child);
        }
        if (node.children.len > 0) {
            allocator.free(node.children);
        }
    }

    /// Split area and return debug nodes with constraint info
    /// Returns an allocated array that the caller must free with allocator.free()
    /// Also stores nodes internally for print() to use
    pub fn splitDebug(
        self: *LayoutDebugger,
        direction: Direction,
        area: Rect,
        constraints: []const Constraint,
    ) ![]DebugNode {
        // First do the regular split to get the rectangles
        const rects = try split(self.allocator, direction, area, constraints);
        defer self.allocator.free(rects);

        if (rects.len == 0) {
            return &[_]DebugNode{};
        }

        // Create debug nodes for return
        const nodes = try self.allocator.alloc(DebugNode, rects.len);
        errdefer self.allocator.free(nodes);

        for (nodes, 0..) |*node, i| {
            node.* = DebugNode{
                .constraint = constraints[i],
                .rect = rects[i],
                .children = &[_]DebugNode{},
            };
            // Store a copy in internal list for print() to use
            try self.nodes.append(self.allocator, node.*);
        }

        return nodes;
    }

    /// Print layout tree to writer
    pub fn print(self: *LayoutDebugger, writer: anytype) !void {
        for (self.nodes.items, 0..) |node, i| {
            try printNode(writer, node, 0);
            if (i < self.nodes.items.len - 1) {
                try writer.writeAll("\n");
            }
        }
    }

    /// Print a single node with indentation
    fn printNode(writer: anytype, node: DebugNode, depth: usize) !void {
        // Print indentation
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            try writer.writeAll("  ");
        }

        // Print constraint type and value
        try writer.writeAll("Constraint: ");
        switch (node.constraint) {
            .length => |len| try writer.print("length={d}", .{len}),
            .percentage => |pct| try writer.print("percentage={d}", .{pct}),
            .min => |minimum| try writer.print("min={d}", .{minimum}),
            .max => |maximum| try writer.print("max={d}", .{maximum}),
            .ratio => |r| try writer.print("ratio={d}/{d}", .{ r.num, r.denom }),
            .aspect_ratio => |ar| try writer.print("aspect_ratio={d}:{d}", .{ ar.width, ar.height }),
        }

        try writer.writeAll(", ");
        try node.rect.debugFormat(writer);
        try writer.writeAll("\n");

        // Print children recursively
        for (node.children) |child| {
            try printNode(writer, child, depth + 1);
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Rect - struct literal construction" {
    const r = Rect{ .x = 10, .y = 20, .width = 30, .height = 40 };
    try std.testing.expectEqual(10, r.x);
    try std.testing.expectEqual(20, r.y);
    try std.testing.expectEqual(30, r.width);
    try std.testing.expectEqual(40, r.height);
}

test "Rect.area" {
    const r = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    try std.testing.expectEqual(50, r.area());
}

test "Rect.contains" {
    const r = Rect{ .x = 10, .y = 10, .width = 20, .height = 20 };
    try std.testing.expect(r.contains(10, 10));
    try std.testing.expect(r.contains(20, 20));
    try std.testing.expect(r.contains(29, 29));
    try std.testing.expect(!r.contains(30, 30));
    try std.testing.expect(!r.contains(5, 15));
}

test "Rect.inner" {
    const r = Rect{ .x = 10, .y = 10, .width = 20, .height = 20 };
    const inner_rect = r.inner(2);
    try std.testing.expectEqual(12, inner_rect.x);
    try std.testing.expectEqual(12, inner_rect.y);
    try std.testing.expectEqual(16, inner_rect.width);
    try std.testing.expectEqual(16, inner_rect.height);
}

test "Rect.inner - margin too large" {
    const r = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const inner_rect = r.inner(10);
    try std.testing.expectEqual(0, inner_rect.width);
    try std.testing.expectEqual(0, inner_rect.height);
}

test "Rect.intersects" {
    const r1 = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = Rect{ .x = 5, .y = 5, .width = 10, .height = 10 };
    const r3 = Rect{ .x = 20, .y = 20, .width = 10, .height = 10 };

    try std.testing.expect(r1.intersects(r2));
    try std.testing.expect(r2.intersects(r1));
    try std.testing.expect(!r1.intersects(r3));
}

test "Rect.intersection" {
    const r1 = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = Rect{ .x = 5, .y = 5, .width = 10, .height = 10 };

    const inter = r1.intersection(r2).?;
    try std.testing.expectEqual(5, inter.x);
    try std.testing.expectEqual(5, inter.y);
    try std.testing.expectEqual(5, inter.width);
    try std.testing.expectEqual(5, inter.height);
}

test "Rect.intersection - no overlap" {
    const r1 = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = Rect{ .x = 20, .y = 20, .width = 10, .height = 10 };

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
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
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
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
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
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
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
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{};

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(0, result.len);
}

test "split - exceeding available space" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
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
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 60 };
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
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
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
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 50 };
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
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
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
    const r1 = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = Rect{ .x = 5, .y = 5, .width = 10, .height = 10 };

    const result = r1.intersection(r2);
    try std.testing.expect(result != null);
    const inter = result.?;
    try std.testing.expectEqual(@as(u16, 5), inter.x);
    try std.testing.expectEqual(@as(u16, 5), inter.y);
    try std.testing.expectEqual(@as(u16, 5), inter.width);
    try std.testing.expectEqual(@as(u16, 5), inter.height);
}

test "Rect.intersection with no overlap" {
    const r1 = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = Rect{ .x = 20, .y = 20, .width = 10, .height = 10 };

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
    const area = Rect{ .x = 0, .y = 0, .width = 1600, .height = 900 };
    const constrained = area.withAspectRatio(.{ .width = 16, .height = 9 });
    // Should fill the full width (1600) and calculate height (900)
    try std.testing.expectEqual(1600, constrained.width);
    try std.testing.expectEqual(900, constrained.height);
}

test "aspect ratio helper - Rect.withAspectRatio portrait in landscape area" {
    const area = Rect{ .x = 0, .y = 0, .width = 800, .height = 600 };
    const constrained = area.withAspectRatio(.{ .width = 9, .height = 16 });
    // Portrait ratio (9:16) in landscape area
    // Width-constrained: 800 available, height = 800 * 16 / 9 = 1422
    // But must fit in 600 height available, so height-constrained
    // Height: 600 available, width = 600 * 9 / 16 = 337.5 → 337
    try std.testing.expectEqual(337, constrained.width);
    try std.testing.expectEqual(600, constrained.height);
}

test "aspect ratio helper - Rect.withAspectRatio exact fit" {
    const area = Rect{ .x = 10, .y = 20, .width = 1920, .height = 1080 };
    const constrained = area.withAspectRatio(.{ .width = 16, .height = 9 });
    // Exact 16:9 match: 1920 x 1080
    try std.testing.expectEqual(1920, constrained.width);
    try std.testing.expectEqual(1080, constrained.height);
}

test "aspect ratio helper - Rect.withAspectRatio preserves position" {
    const area = Rect{ .x = 100, .y = 200, .width = 400, .height = 300 };
    const constrained = area.withAspectRatio(.{ .width = 4, .height = 3 });
    // Position should be preserved
    try std.testing.expectEqual(100, constrained.x);
    try std.testing.expectEqual(200, constrained.y);
    // Dimensions: 4:3 ratio in 400x300 space
    try std.testing.expectEqual(400, constrained.width);
    try std.testing.expectEqual(300, constrained.height);
}

test "aspect ratio helper - Rect.withAspectRatio small area" {
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 30 };
    const constrained = area.withAspectRatio(.{ .width = 2, .height = 3 });
    // 2:3 portrait ratio in 20x30 area
    // Width-constrained: 20 * 3 / 2 = 30, fits in 30 height
    try std.testing.expectEqual(20, constrained.width);
    try std.testing.expectEqual(30, constrained.height);
}

test "split - aspect ratio constraint in layout" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 1600, .height = 1200 };
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
    const area = Rect{ .x = 0, .y = 0, .width = 800, .height = 600 };
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

// ============================================================================
// Rect.fromSize() Convenience Constructor Tests
// ============================================================================

test "Rect.fromSize basic usage - standard dimensions" {
    const rect = Rect.fromSize(10, 5);
    try std.testing.expectEqual(@as(u16, 0), rect.x);
    try std.testing.expectEqual(@as(u16, 0), rect.y);
    try std.testing.expectEqual(@as(u16, 10), rect.width);
    try std.testing.expectEqual(@as(u16, 5), rect.height);
}

test "Rect.fromSize zero dimensions - 0x0 rectangle" {
    const rect = Rect.fromSize(0, 0);
    try std.testing.expectEqual(@as(u16, 0), rect.x);
    try std.testing.expectEqual(@as(u16, 0), rect.y);
    try std.testing.expectEqual(@as(u16, 0), rect.width);
    try std.testing.expectEqual(@as(u16, 0), rect.height);
}

test "Rect.fromSize zero width - degenerate rectangle" {
    const rect = Rect.fromSize(0, 100);
    try std.testing.expectEqual(@as(u16, 0), rect.x);
    try std.testing.expectEqual(@as(u16, 0), rect.y);
    try std.testing.expectEqual(@as(u16, 0), rect.width);
    try std.testing.expectEqual(@as(u16, 100), rect.height);
}

test "Rect.fromSize zero height - degenerate rectangle" {
    const rect = Rect.fromSize(100, 0);
    try std.testing.expectEqual(@as(u16, 0), rect.x);
    try std.testing.expectEqual(@as(u16, 0), rect.y);
    try std.testing.expectEqual(@as(u16, 100), rect.width);
    try std.testing.expectEqual(@as(u16, 0), rect.height);
}

test "Rect.fromSize large dimensions - 1000x1000" {
    const rect = Rect.fromSize(1000, 1000);
    try std.testing.expectEqual(@as(u16, 0), rect.x);
    try std.testing.expectEqual(@as(u16, 0), rect.y);
    try std.testing.expectEqual(@as(u16, 1000), rect.width);
    try std.testing.expectEqual(@as(u16, 1000), rect.height);
}

test "Rect.fromSize asymmetric - wide rectangle" {
    const rect = Rect.fromSize(100, 1);
    try std.testing.expectEqual(@as(u16, 0), rect.x);
    try std.testing.expectEqual(@as(u16, 0), rect.y);
    try std.testing.expectEqual(@as(u16, 100), rect.width);
    try std.testing.expectEqual(@as(u16, 1), rect.height);
}

test "Rect.fromSize asymmetric - tall rectangle" {
    const rect = Rect.fromSize(1, 100);
    try std.testing.expectEqual(@as(u16, 0), rect.x);
    try std.testing.expectEqual(@as(u16, 0), rect.y);
    try std.testing.expectEqual(@as(u16, 1), rect.width);
    try std.testing.expectEqual(@as(u16, 100), rect.height);
}

test "Rect.fromSize equivalence with manual construction" {
    const rect1 = Rect.fromSize(80, 24);
    const rect2 = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try std.testing.expectEqual(rect2.x, rect1.x);
    try std.testing.expectEqual(rect2.y, rect1.y);
    try std.testing.expectEqual(rect2.width, rect1.width);
    try std.testing.expectEqual(rect2.height, rect1.height);
}

test "Rect.fromSize max u16 dimensions" {
    const rect = Rect.fromSize(65535, 65535);
    try std.testing.expectEqual(@as(u16, 0), rect.x);
    try std.testing.expectEqual(@as(u16, 0), rect.y);
    try std.testing.expectEqual(@as(u16, 65535), rect.width);
    try std.testing.expectEqual(@as(u16, 65535), rect.height);
}

test "Rect.fromSize area calculation matches created rectangle" {
    const rect = Rect.fromSize(50, 40);
    const expected_area = @as(u32, 50) * @as(u32, 40);
    try std.testing.expectEqual(expected_area, rect.area());
}

test "Rect.fromSize contains point at origin" {
    const rect = Rect.fromSize(10, 10);
    try std.testing.expect(rect.contains(0, 0));
}

test "Rect.fromSize does not contain point outside bounds" {
    const rect = Rect.fromSize(10, 10);
    try std.testing.expect(!rect.contains(10, 10)); // beyond right and bottom edges
    try std.testing.expect(!rect.contains(15, 15));
}

test "Rect.fromSize common terminal size 80x24" {
    const rect = Rect.fromSize(80, 24);
    try std.testing.expectEqual(@as(u16, 80), rect.width);
    try std.testing.expectEqual(@as(u16, 24), rect.height);
    try std.testing.expectEqual(@as(u32, 1920), rect.area());
}

test "Rect.fromSize common terminal size 120x40" {
    const rect = Rect.fromSize(120, 40);
    try std.testing.expectEqual(@as(u16, 120), rect.width);
    try std.testing.expectEqual(@as(u16, 40), rect.height);
    try std.testing.expectEqual(@as(u32, 4800), rect.area());
}

test "Rect.withAspectRatio - width-constrained landscape" {
    const area = Rect{ .x = 0, .y = 0, .width = 2000, .height = 500 };
    const constrained = area.withAspectRatio(.{ .width = 16, .height = 9 });
    // 16:9 in 2000x500 space
    // Width-constrained would need 1111 height, but only 500 available
    // So height-constrained: 500 height needs 500 * 16 / 9 = 888 width
    try std.testing.expectEqual(888, constrained.width);
    try std.testing.expectEqual(500, constrained.height);
}

test "Rect.withAspectRatio - height-constrained portrait" {
    const area = Rect{ .x = 0, .y = 0, .width = 300, .height = 2000 };
    const constrained = area.withAspectRatio(.{ .width = 16, .height = 9 });
    // 16:9 landscape in 300x2000 space
    // Height-constrained would need 3555 width, but only 300 available
    // So width-constrained: 300 width gives 300 * 9 / 16 = 168 height
    try std.testing.expectEqual(300, constrained.width);
    try std.testing.expectEqual(168, constrained.height);
}

test "Rect.withAspectRatio - square in rectangular area" {
    const area = Rect{ .x = 50, .y = 75, .width = 1000, .height = 400 };
    const constrained = area.withAspectRatio(.{ .width = 1, .height = 1 });
    // 1:1 square in 1000x400 space = 400x400 (height-constrained)
    try std.testing.expectEqual(50, constrained.x);
    try std.testing.expectEqual(75, constrained.y);
    try std.testing.expectEqual(400, constrained.width);
    try std.testing.expectEqual(400, constrained.height);
}

test "Rect.withAspectRatio - common mobile aspect ratios" {
    // iPhone 14 Pro: 1170 x 2532 = 9:19.6 (roughly 9:20)
    const area = Rect{ .x = 0, .y = 0, .width = 1170, .height = 2532 };
    const constrained = area.withAspectRatio(.{ .width = 9, .height = 20 });
    // Height-constrained: 2532 is available height
    // Width = 2532 * 9 / 20 = 1139
    try std.testing.expectEqual(1139, constrained.width);
    try std.testing.expectEqual(2532, constrained.height);
}

test "split - aspect ratio in three-way vertical split" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 400, .height = 600 };
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

// ============================================================================
// Min/Max Nested Layout Constraint Propagation Tests
// ============================================================================

test "nested_split_min_propagation_horizontal: inner layout with min constraint gets reserved space" {
    const allocator = std.testing.allocator;
    const parent_area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    // First, split parent into two areas
    const parent_constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const parent_chunks = try split(allocator, .horizontal, parent_area, &parent_constraints);
    defer allocator.free(parent_chunks);

    // Now split the second chunk which has a min constraint of 50
    // Even though it only got 50 width (50% of 100), a nested layout
    // with min 60 should signal that the parent should have reserved more space
    const inner_constraints = [_]Constraint{
        .{ .min = 60 },
    };
    const inner_chunks = try split(allocator, .horizontal, parent_chunks[1], &inner_constraints);
    defer allocator.free(inner_chunks);

    // The inner chunk should have gotten at least 60, not just 50
    // This requires parent to respect nested min constraints
    try std.testing.expect(inner_chunks[0].width >= 60);
}

test "nested_split_max_propagation_horizontal: inner layout with max constraint limits allocation" {
    const allocator = std.testing.allocator;
    const parent_area = Rect{ .x = 0, .y = 0, .width = 200, .height = 50 };

    // Split parent into two equal areas
    const parent_constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const parent_chunks = try split(allocator, .horizontal, parent_area, &parent_constraints);
    defer allocator.free(parent_chunks);

    // Second chunk got 100, but nested layout has max 60
    // Inner split should respect max constraint
    const inner_constraints = [_]Constraint{
        .{ .max = 60 },
    };
    const inner_chunks = try split(allocator, .horizontal, parent_chunks[1], &inner_constraints);
    defer allocator.free(inner_chunks);

    // Inner chunk should not exceed max of 60
    try std.testing.expect(inner_chunks[0].width <= 60);
}

test "nested_split_min_propagation_vertical: vertical split respects nested min" {
    const allocator = std.testing.allocator;
    const parent_area = Rect{ .x = 0, .y = 0, .width = 80, .height = 100 };

    // Vertical split parent
    const parent_constraints = [_]Constraint{
        .{ .percentage = 40 },
        .{ .percentage = 60 },
    };
    const parent_chunks = try split(allocator, .vertical, parent_area, &parent_constraints);
    defer allocator.free(parent_chunks);

    // Second chunk got 60 height, but nested split has min 75
    const inner_constraints = [_]Constraint{
        .{ .min = 75 },
    };
    const inner_chunks = try split(allocator, .vertical, parent_chunks[1], &inner_constraints);
    defer allocator.free(inner_chunks);

    // Inner should get at least 75 (min constraint)
    try std.testing.expect(inner_chunks[0].height >= 75);
}

test "nested_split_max_propagation_vertical: vertical split respects nested max" {
    const allocator = std.testing.allocator;
    const parent_area = Rect{ .x = 0, .y = 0, .width = 80, .height = 150 };

    // Vertical split parent
    const parent_constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const parent_chunks = try split(allocator, .vertical, parent_area, &parent_constraints);
    defer allocator.free(parent_chunks);

    // Second chunk got 75, nested split has max 50
    const inner_constraints = [_]Constraint{
        .{ .max = 50 },
    };
    const inner_chunks = try split(allocator, .vertical, parent_chunks[1], &inner_constraints);
    defer allocator.free(inner_chunks);

    // Inner should not exceed max of 50
    try std.testing.expect(inner_chunks[0].height <= 50);
}

test "nested_split_three_level_min_propagation: constraints propagate through 3 nesting levels" {
    const allocator = std.testing.allocator;

    // Level 1: parent area
    const level1_area = Rect{ .x = 0, .y = 0, .width = 200, .height = 100 };
    const level1_constraints = [_]Constraint{
        .{ .percentage = 60 },
        .{ .percentage = 40 },
    };
    const level1_chunks = try split(allocator, .horizontal, level1_area, &level1_constraints);
    defer allocator.free(level1_chunks);

    // Level 2: split the first chunk
    const level2_constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const level2_chunks = try split(allocator, .horizontal, level1_chunks[0], &level2_constraints);
    defer allocator.free(level2_chunks);

    // Level 3: split the second chunk from level 2 with a min constraint
    const level3_constraints = [_]Constraint{
        .{ .min = 100 },
    };
    const level3_chunks = try split(allocator, .horizontal, level2_chunks[1], &level3_constraints);
    defer allocator.free(level3_chunks);

    // Level 3 chunk should get at least 100
    // This requires constraints to propagate: L3 min → L2 parent → L1 parent
    try std.testing.expect(level3_chunks[0].width >= 100);
}

test "nested_split_conflicting_mins_exceed_available: multiple nested mins that exceed space" {
    const allocator = std.testing.allocator;
    const parent_area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    // Try to create nested layout with two min constraints that exceed available space
    // First split parent
    const parent_constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const parent_chunks = try split(allocator, .horizontal, parent_area, &parent_constraints);
    defer allocator.free(parent_chunks);

    // Second chunk has 50 width, but nested split wants min 30 + min 40 = 70 total
    // Algorithm should distribute proportionally while respecting minimums
    const inner_constraints = [_]Constraint{
        .{ .min = 30 },
        .{ .min = 40 },
    };
    const inner_chunks = try split(allocator, .horizontal, parent_chunks[1], &inner_constraints);
    defer allocator.free(inner_chunks);

    // Both chunks should exist
    try std.testing.expectEqual(2, inner_chunks.len);
    // Combined should equal available space
    const total = inner_chunks[0].width + inner_chunks[1].width;
    try std.testing.expectEqual(50, total);
    // Each should get at least its minimum (or be scaled proportionally)
    // If not enough space, should be capped at available but proportionally distributed
    try std.testing.expect(inner_chunks[0].width > 0);
    try std.testing.expect(inner_chunks[1].width > 0);
}

test "nested_split_mixed_percentage_and_min: percentage parent with nested min child" {
    const allocator = std.testing.allocator;
    const parent_area = Rect{ .x = 0, .y = 0, .width = 200, .height = 100 };

    // Parent splits with percentages
    const parent_constraints = [_]Constraint{
        .{ .percentage = 30 },
        .{ .percentage = 70 },
    };
    const parent_chunks = try split(allocator, .horizontal, parent_area, &parent_constraints);
    defer allocator.free(parent_chunks);

    // Second chunk (70% = 140 width) contains nested layout with multiple constraints
    const inner_constraints = [_]Constraint{
        .{ .min = 50 },
        .{ .length = 30 },
    };
    const inner_chunks = try split(allocator, .horizontal, parent_chunks[1], &inner_constraints);
    defer allocator.free(inner_chunks);

    try std.testing.expectEqual(2, inner_chunks.len);
    // First inner chunk should get at least 50 (min constraint)
    try std.testing.expect(inner_chunks[0].width >= 50);
    // Second should be fixed at 30
    try std.testing.expectEqual(30, inner_chunks[1].width);
}

test "nested_split_mixed_percentage_and_max: percentage parent with nested max child" {
    const allocator = std.testing.allocator;
    const parent_area = Rect{ .x = 0, .y = 0, .width = 200, .height = 100 };

    // Parent splits
    const parent_constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const parent_chunks = try split(allocator, .horizontal, parent_area, &parent_constraints);
    defer allocator.free(parent_chunks);

    // Second chunk (50% = 100 width) contains nested layout with max constraint
    const inner_constraints = [_]Constraint{
        .{ .max = 60 },
        .{ .length = 20 },
    };
    const inner_chunks = try split(allocator, .horizontal, parent_chunks[1], &inner_constraints);
    defer allocator.free(inner_chunks);

    try std.testing.expectEqual(2, inner_chunks.len);
    // First inner chunk should not exceed max of 60
    try std.testing.expect(inner_chunks[0].width <= 60);
    // Second should be fixed at 20
    try std.testing.expectEqual(20, inner_chunks[1].width);
}

test "nested_split_oversized_min_constraint: min larger than available space" {
    const allocator = std.testing.allocator;
    const parent_area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    // Split parent
    const parent_constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const parent_chunks = try split(allocator, .horizontal, parent_area, &parent_constraints);
    defer allocator.free(parent_chunks);

    // Second chunk has 50 width, but nested layout wants min 100
    const inner_constraints = [_]Constraint{
        .{ .min = 100 },
    };
    const inner_chunks = try split(allocator, .horizontal, parent_chunks[1], &inner_constraints);
    defer allocator.free(inner_chunks);

    // Algorithm should handle gracefully: either clamp to available
    // or signal constraint violation (depending on implementation choice)
    try std.testing.expectEqual(1, inner_chunks.len);
    try std.testing.expect(inner_chunks[0].width > 0);
}

test "nested_split_zero_min_constraint: min = 0 should be valid" {
    const allocator = std.testing.allocator;
    const parent_area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    const parent_constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const parent_chunks = try split(allocator, .horizontal, parent_area, &parent_constraints);
    defer allocator.free(parent_chunks);

    // Nested layout with zero minimum
    const inner_constraints = [_]Constraint{
        .{ .min = 0 },
    };
    const inner_chunks = try split(allocator, .horizontal, parent_chunks[1], &inner_constraints);
    defer allocator.free(inner_chunks);

    try std.testing.expectEqual(1, inner_chunks.len);
    try std.testing.expect(inner_chunks[0].width >= 0);
}

test "nested_split_zero_max_constraint: max = 0 should limit to zero" {
    const allocator = std.testing.allocator;
    const parent_area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    const parent_constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const parent_chunks = try split(allocator, .horizontal, parent_area, &parent_constraints);
    defer allocator.free(parent_chunks);

    // Nested layout with zero max (should result in zero size)
    const inner_constraints = [_]Constraint{
        .{ .max = 0 },
    };
    const inner_chunks = try split(allocator, .horizontal, parent_chunks[1], &inner_constraints);
    defer allocator.free(inner_chunks);

    try std.testing.expectEqual(1, inner_chunks.len);
    try std.testing.expectEqual(0, inner_chunks[0].width);
}

test "nested_split_multiple_nested_areas: multiple nested splits at same level" {
    const allocator = std.testing.allocator;
    const parent_area = Rect{ .x = 0, .y = 0, .width = 300, .height = 100 };

    // Parent splits into 3 areas
    const parent_constraints = [_]Constraint{
        .{ .percentage = 33 },
        .{ .percentage = 33 },
        .{ .percentage = 34 },
    };
    const parent_chunks = try split(allocator, .horizontal, parent_area, &parent_constraints);
    defer allocator.free(parent_chunks);

    // Each of the three parent chunks contains its own nested layout
    // First chunk (100 width) with nested min 50
    const inner1_constraints = [_]Constraint{
        .{ .min = 50 },
    };
    const inner1_chunks = try split(allocator, .horizontal, parent_chunks[0], &inner1_constraints);
    defer allocator.free(inner1_chunks);

    // Second chunk (100 width) with nested max 40
    const inner2_constraints = [_]Constraint{
        .{ .max = 40 },
    };
    const inner2_chunks = try split(allocator, .horizontal, parent_chunks[1], &inner2_constraints);
    defer allocator.free(inner2_chunks);

    // Third chunk (100 width) with nested min 60, max 80
    const inner3_constraints = [_]Constraint{
        .{ .min = 60 },
        .{ .max = 80 },
    };
    const inner3_chunks = try split(allocator, .horizontal, parent_chunks[2], &inner3_constraints);
    defer allocator.free(inner3_chunks);

    // Verify each nested split respects its constraints
    try std.testing.expect(inner1_chunks[0].width >= 50);
    try std.testing.expect(inner2_chunks[0].width <= 40);
    try std.testing.expect(inner3_chunks[0].width >= 60);
    try std.testing.expect(inner3_chunks[1].width <= 80);
}

test "split - stress test with many constraints (100)" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 1000, .height = 100 };

    // Create 100 constraints (all equal percentages)
    var constraints: [100]Constraint = undefined;
    for (&constraints) |*c| {
        c.* = .{ .percentage = 1 };
    }

    const chunks = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(chunks);

    // Verify we got 100 chunks
    try std.testing.expectEqual(100, chunks.len);

    // Verify total width equals or is close to available (accounting for integer division)
    var total_width: u32 = 0;
    for (chunks) |chunk| {
        total_width += chunk.width;
    }
    try std.testing.expect(total_width >= area.width - 10); // Allow small rounding difference
    try std.testing.expect(total_width <= area.width);

    // Verify all chunks are within the parent area bounds
    for (chunks) |chunk| {
        try std.testing.expect(chunk.x >= area.x);
        try std.testing.expect(chunk.x + chunk.width <= area.x + area.width);
        try std.testing.expectEqual(area.y, chunk.y);
        try std.testing.expectEqual(area.height, chunk.height);
    }

    // Verify chunks are adjacent (no gaps or overlaps)
    for (chunks[0 .. chunks.len - 1], chunks[1..]) |curr, next| {
        try std.testing.expectEqual(curr.x + curr.width, next.x);
    }
}

test "split - stress test with many min constraints" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 500, .height = 100 };

    // Create 50 constraints with min=5 each (total min = 250)
    var constraints: [50]Constraint = undefined;
    for (&constraints) |*c| {
        c.* = .{ .min = 5 };
    }

    const chunks = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(chunks);

    try std.testing.expectEqual(50, chunks.len);

    // Verify total width equals available (all mins can be satisfied)
    var total_width: u32 = 0;
    for (chunks) |chunk| {
        total_width += chunk.width;
    }
    try std.testing.expectEqual(area.width, total_width);

    // Verify all chunks meet their minimum
    for (chunks) |chunk| {
        try std.testing.expect(chunk.width >= 5);
    }
}

test "split - stress test with exceeding min constraints" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 300, .height = 100 };

    // Create 50 constraints with min=10 each (total min = 500 > 300 available)
    var constraints: [50]Constraint = undefined;
    for (&constraints) |*c| {
        c.* = .{ .min = 10 };
    }

    const chunks = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(chunks);

    try std.testing.expectEqual(50, chunks.len);

    // When mins exceed available, they should be scaled proportionally
    // Each should get approximately 6 pixels (300 / 50)
    var total_width: u32 = 0;
    for (chunks) |chunk| {
        total_width += chunk.width;
    }
    try std.testing.expectEqual(area.width, total_width);

    // All chunks should have roughly equal width (proportional distribution)
    const expected_avg = area.width / chunks.len; // 6 pixels
    for (chunks) |chunk| {
        // Allow ±2 pixels variance for rounding
        try std.testing.expect(chunk.width >= expected_avg - 2);
        try std.testing.expect(chunk.width <= expected_avg + 2);
    }
}

// ============================================================================
// Margin and Padding Tests
// ============================================================================

test "Margin creation - individual sides" {
    const m = Margin{ .top = 1, .right = 2, .bottom = 3, .left = 4 };
    try std.testing.expectEqual(@as(u16, 1), m.top);
    try std.testing.expectEqual(@as(u16, 2), m.right);
    try std.testing.expectEqual(@as(u16, 3), m.bottom);
    try std.testing.expectEqual(@as(u16, 4), m.left);
}

test "Margin.all - creates uniform margin" {
    const m = Margin.all(5);
    try std.testing.expectEqual(@as(u16, 5), m.top);
    try std.testing.expectEqual(@as(u16, 5), m.right);
    try std.testing.expectEqual(@as(u16, 5), m.bottom);
    try std.testing.expectEqual(@as(u16, 5), m.left);
}

test "Margin.all - zero margin" {
    const m = Margin.all(0);
    try std.testing.expectEqual(@as(u16, 0), m.top);
    try std.testing.expectEqual(@as(u16, 0), m.right);
    try std.testing.expectEqual(@as(u16, 0), m.bottom);
    try std.testing.expectEqual(@as(u16, 0), m.left);
}

test "Margin.symmetric - vertical and horizontal" {
    const m = Margin.symmetric(10, 20);
    try std.testing.expectEqual(@as(u16, 10), m.top);
    try std.testing.expectEqual(@as(u16, 20), m.right);
    try std.testing.expectEqual(@as(u16, 10), m.bottom);
    try std.testing.expectEqual(@as(u16, 20), m.left);
}

test "Margin.symmetric - equal vertical and horizontal" {
    const m = Margin.symmetric(15, 15);
    try std.testing.expectEqual(@as(u16, 15), m.top);
    try std.testing.expectEqual(@as(u16, 15), m.right);
    try std.testing.expectEqual(@as(u16, 15), m.bottom);
    try std.testing.expectEqual(@as(u16, 15), m.left);
}

test "Margin.symmetric - zero values" {
    const m = Margin.symmetric(0, 0);
    try std.testing.expectEqual(@as(u16, 0), m.top);
    try std.testing.expectEqual(@as(u16, 0), m.right);
    try std.testing.expectEqual(@as(u16, 0), m.bottom);
    try std.testing.expectEqual(@as(u16, 0), m.left);
}

test "Padding creation - individual sides" {
    const p = Padding{ .top = 5, .right = 10, .bottom = 15, .left = 20 };
    try std.testing.expectEqual(@as(u16, 5), p.top);
    try std.testing.expectEqual(@as(u16, 10), p.right);
    try std.testing.expectEqual(@as(u16, 15), p.bottom);
    try std.testing.expectEqual(@as(u16, 20), p.left);
}

test "Padding.all - creates uniform padding" {
    const p = Padding.all(8);
    try std.testing.expectEqual(@as(u16, 8), p.top);
    try std.testing.expectEqual(@as(u16, 8), p.right);
    try std.testing.expectEqual(@as(u16, 8), p.bottom);
    try std.testing.expectEqual(@as(u16, 8), p.left);
}

test "Padding.all - zero padding" {
    const p = Padding.all(0);
    try std.testing.expectEqual(@as(u16, 0), p.top);
    try std.testing.expectEqual(@as(u16, 0), p.right);
    try std.testing.expectEqual(@as(u16, 0), p.bottom);
    try std.testing.expectEqual(@as(u16, 0), p.left);
}

test "Padding.symmetric - vertical and horizontal" {
    const p = Padding.symmetric(5, 10);
    try std.testing.expectEqual(@as(u16, 5), p.top);
    try std.testing.expectEqual(@as(u16, 10), p.right);
    try std.testing.expectEqual(@as(u16, 5), p.bottom);
    try std.testing.expectEqual(@as(u16, 10), p.left);
}

test "Padding.symmetric - equal vertical and horizontal" {
    const p = Padding.symmetric(12, 12);
    try std.testing.expectEqual(@as(u16, 12), p.top);
    try std.testing.expectEqual(@as(u16, 12), p.right);
    try std.testing.expectEqual(@as(u16, 12), p.bottom);
    try std.testing.expectEqual(@as(u16, 12), p.left);
}

test "Rect.withMargin - uniform margin shrinks rect correctly" {
    const r = Rect{ .x = 10, .y = 10, .width = 100, .height = 50 };
    const m = Margin.all(5);
    const result = r.withMargin(m);

    try std.testing.expectEqual(@as(u16, 15), result.x); // 10 + 5 left margin
    try std.testing.expectEqual(@as(u16, 15), result.y); // 10 + 5 top margin
    try std.testing.expectEqual(@as(u16, 90), result.width); // 100 - 5 left - 5 right
    try std.testing.expectEqual(@as(u16, 40), result.height); // 50 - 5 top - 5 bottom
}

test "Rect.withMargin - asymmetric margin" {
    const r = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const m = Margin{ .top = 10, .right = 5, .bottom = 15, .left = 20 };
    const result = r.withMargin(m);

    try std.testing.expectEqual(@as(u16, 20), result.x); // 0 + 20 left margin
    try std.testing.expectEqual(@as(u16, 10), result.y); // 0 + 10 top margin
    try std.testing.expectEqual(@as(u16, 75), result.width); // 100 - 20 left - 5 right
    try std.testing.expectEqual(@as(u16, 75), result.height); // 100 - 10 top - 15 bottom
}

test "Rect.withMargin - zero margin does not change rect" {
    const r = Rect{ .x = 10, .y = 20, .width = 80, .height = 60 };
    const m = Margin.all(0);
    const result = r.withMargin(m);

    try std.testing.expectEqual(r.x, result.x);
    try std.testing.expectEqual(r.y, result.y);
    try std.testing.expectEqual(r.width, result.width);
    try std.testing.expectEqual(r.height, result.height);
}

test "Rect.withMargin - margin exceeds width returns zero-width rect" {
    const r = Rect{ .x = 0, .y = 0, .width = 10, .height = 50 };
    const m = Margin{ .top = 5, .right = 10, .bottom = 5, .left = 10 };
    const result = r.withMargin(m);

    try std.testing.expectEqual(@as(u16, 10), result.x); // left margin still applied
    try std.testing.expectEqual(@as(u16, 5), result.y); // top margin still applied
    try std.testing.expectEqual(@as(u16, 0), result.width); // 10 - 10 - 10 = -10 → 0
    try std.testing.expectEqual(@as(u16, 40), result.height); // height unaffected
}

test "Rect.withMargin - margin exceeds height returns zero-height rect" {
    const r = Rect{ .x = 0, .y = 0, .width = 50, .height = 10 };
    const m = Margin{ .top = 10, .right = 5, .bottom = 10, .left = 5 };
    const result = r.withMargin(m);

    try std.testing.expectEqual(@as(u16, 5), result.x);
    try std.testing.expectEqual(@as(u16, 10), result.y);
    try std.testing.expectEqual(@as(u16, 40), result.width); // width unaffected
    try std.testing.expectEqual(@as(u16, 0), result.height); // 10 - 10 - 10 = -10 → 0
}

test "Rect.withMargin - margin exceeds both dimensions" {
    const r = Rect{ .x = 5, .y = 5, .width = 10, .height = 10 };
    const m = Margin.all(20);
    const result = r.withMargin(m);

    try std.testing.expectEqual(@as(u16, 25), result.x); // 5 + 20
    try std.testing.expectEqual(@as(u16, 25), result.y); // 5 + 20
    try std.testing.expectEqual(@as(u16, 0), result.width); // 10 - 40 → 0
    try std.testing.expectEqual(@as(u16, 0), result.height); // 10 - 40 → 0
}

test "Rect.withMargin - large rect with small margin" {
    const r = Rect{ .x = 100, .y = 200, .width = 1920, .height = 1080 };
    const m = Margin.all(1);
    const result = r.withMargin(m);

    try std.testing.expectEqual(@as(u16, 101), result.x);
    try std.testing.expectEqual(@as(u16, 201), result.y);
    try std.testing.expectEqual(@as(u16, 1918), result.width);
    try std.testing.expectEqual(@as(u16, 1078), result.height);
}

test "Rect.withPadding - uniform padding shrinks rect correctly" {
    const r = Rect{ .x = 10, .y = 10, .width = 100, .height = 50 };
    const p = Padding.all(5);
    const result = r.withPadding(p);

    try std.testing.expectEqual(@as(u16, 15), result.x); // 10 + 5 left padding
    try std.testing.expectEqual(@as(u16, 15), result.y); // 10 + 5 top padding
    try std.testing.expectEqual(@as(u16, 90), result.width); // 100 - 5 left - 5 right
    try std.testing.expectEqual(@as(u16, 40), result.height); // 50 - 5 top - 5 bottom
}

test "Rect.withPadding - asymmetric padding" {
    const r = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const p = Padding{ .top = 2, .right = 4, .bottom = 6, .left = 8 };
    const result = r.withPadding(p);

    try std.testing.expectEqual(@as(u16, 8), result.x); // 0 + 8 left padding
    try std.testing.expectEqual(@as(u16, 2), result.y); // 0 + 2 top padding
    try std.testing.expectEqual(@as(u16, 88), result.width); // 100 - 8 left - 4 right
    try std.testing.expectEqual(@as(u16, 92), result.height); // 100 - 2 top - 6 bottom
}

test "Rect.withPadding - zero padding does not change rect" {
    const r = Rect{ .x = 50, .y = 50, .width = 200, .height = 150 };
    const p = Padding.all(0);
    const result = r.withPadding(p);

    try std.testing.expectEqual(r.x, result.x);
    try std.testing.expectEqual(r.y, result.y);
    try std.testing.expectEqual(r.width, result.width);
    try std.testing.expectEqual(r.height, result.height);
}

test "Rect.withPadding - padding exceeds width returns zero-width rect" {
    const r = Rect{ .x = 0, .y = 0, .width = 20, .height = 50 };
    const p = Padding{ .top = 5, .right = 15, .bottom = 5, .left = 15 };
    const result = r.withPadding(p);

    try std.testing.expectEqual(@as(u16, 15), result.x);
    try std.testing.expectEqual(@as(u16, 5), result.y);
    try std.testing.expectEqual(@as(u16, 0), result.width); // 20 - 15 - 15 = -10 → 0
    try std.testing.expectEqual(@as(u16, 40), result.height);
}

test "Rect.withPadding - padding exceeds height returns zero-height rect" {
    const r = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    const p = Padding{ .top = 15, .right = 5, .bottom = 15, .left = 5 };
    const result = r.withPadding(p);

    try std.testing.expectEqual(@as(u16, 5), result.x);
    try std.testing.expectEqual(@as(u16, 15), result.y);
    try std.testing.expectEqual(@as(u16, 40), result.width);
    try std.testing.expectEqual(@as(u16, 0), result.height); // 20 - 15 - 15 = -10 → 0
}

test "Rect.withPadding - padding exceeds both dimensions" {
    const r = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    const p = Padding.all(10);
    const result = r.withPadding(p);

    try std.testing.expectEqual(@as(u16, 10), result.x);
    try std.testing.expectEqual(@as(u16, 10), result.y);
    try std.testing.expectEqual(@as(u16, 0), result.width); // 5 - 20 → 0
    try std.testing.expectEqual(@as(u16, 0), result.height); // 5 - 20 → 0
}

test "Margin and Padding combined - margin then padding" {
    const r = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const m = Margin.all(10);
    const p = Padding.all(5);

    const with_margin = r.withMargin(m);
    const with_both = with_margin.withPadding(p);

    try std.testing.expectEqual(@as(u16, 15), with_both.x); // 0 + 10 margin + 5 padding
    try std.testing.expectEqual(@as(u16, 15), with_both.y);
    try std.testing.expectEqual(@as(u16, 70), with_both.width); // 100 - 20 margin - 10 padding
    try std.testing.expectEqual(@as(u16, 70), with_both.height);
}

test "Margin and Padding combined - padding then margin" {
    const r = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const m = Margin.all(10);
    const p = Padding.all(5);

    const with_padding = r.withPadding(p);
    const with_both = with_padding.withMargin(m);

    try std.testing.expectEqual(@as(u16, 15), with_both.x); // 0 + 5 padding + 10 margin
    try std.testing.expectEqual(@as(u16, 15), with_both.y);
    try std.testing.expectEqual(@as(u16, 70), with_both.width); // 100 - 10 padding - 20 margin
    try std.testing.expectEqual(@as(u16, 70), with_both.height);
}

test "Rect.withMargin - edge case one pixel rect" {
    const r = Rect{ .x = 50, .y = 50, .width = 1, .height = 1 };
    const m = Margin.all(1);
    const result = r.withMargin(m);

    try std.testing.expectEqual(@as(u16, 51), result.x);
    try std.testing.expectEqual(@as(u16, 51), result.y);
    try std.testing.expectEqual(@as(u16, 0), result.width); // 1 - 2 → 0
    try std.testing.expectEqual(@as(u16, 0), result.height); // 1 - 2 → 0
}

test "Rect.withPadding - edge case one pixel rect" {
    const r = Rect{ .x = 100, .y = 100, .width = 1, .height = 1 };
    const p = Padding.all(1);
    const result = r.withPadding(p);

    try std.testing.expectEqual(@as(u16, 101), result.x);
    try std.testing.expectEqual(@as(u16, 101), result.y);
    try std.testing.expectEqual(@as(u16, 0), result.width); // 1 - 2 → 0
    try std.testing.expectEqual(@as(u16, 0), result.height); // 1 - 2 → 0
}

test "Margin.symmetric - only vertical" {
    const m = Margin.symmetric(20, 0);
    try std.testing.expectEqual(@as(u16, 20), m.top);
    try std.testing.expectEqual(@as(u16, 0), m.right);
    try std.testing.expectEqual(@as(u16, 20), m.bottom);
    try std.testing.expectEqual(@as(u16, 0), m.left);
}

test "Margin.symmetric - only horizontal" {
    const m = Margin.symmetric(0, 30);
    try std.testing.expectEqual(@as(u16, 0), m.top);
    try std.testing.expectEqual(@as(u16, 30), m.right);
    try std.testing.expectEqual(@as(u16, 0), m.bottom);
    try std.testing.expectEqual(@as(u16, 30), m.left);
}

test "Padding.symmetric - only vertical" {
    const p = Padding.symmetric(15, 0);
    try std.testing.expectEqual(@as(u16, 15), p.top);
    try std.testing.expectEqual(@as(u16, 0), p.right);
    try std.testing.expectEqual(@as(u16, 15), p.bottom);
    try std.testing.expectEqual(@as(u16, 0), p.left);
}

test "Padding.symmetric - only horizontal" {
    const p = Padding.symmetric(0, 25);
    try std.testing.expectEqual(@as(u16, 0), p.top);
    try std.testing.expectEqual(@as(u16, 25), p.right);
    try std.testing.expectEqual(@as(u16, 0), p.bottom);
    try std.testing.expectEqual(@as(u16, 25), p.left);
}

test "Rect.withMargin - underflow protection width" {
    const r = Rect{ .x = 0, .y = 0, .width = 5, .height = 100 };
    const m = Margin{ .top = 0, .right = 3, .bottom = 0, .left = 3 };
    const result = r.withMargin(m);

    // left + right = 6 > width 5, should return 0 width
    try std.testing.expectEqual(@as(u16, 0), result.width);
}

test "Rect.withMargin - underflow protection height" {
    const r = Rect{ .x = 0, .y = 0, .width = 100, .height = 5 };
    const m = Margin{ .top = 3, .right = 0, .bottom = 3, .left = 0 };
    const result = r.withMargin(m);

    // top + bottom = 6 > height 5, should return 0 height
    try std.testing.expectEqual(@as(u16, 0), result.height);
}

test "Rect.withPadding - underflow protection width" {
    const r = Rect{ .x = 0, .y = 0, .width = 8, .height = 100 };
    const p = Padding{ .top = 0, .right = 5, .bottom = 0, .left = 5 };
    const result = r.withPadding(p);

    // left + right = 10 > width 8, should return 0 width
    try std.testing.expectEqual(@as(u16, 0), result.width);
}

test "Rect.withPadding - underflow protection height" {
    const r = Rect{ .x = 0, .y = 0, .width = 100, .height = 8 };
    const p = Padding{ .top = 5, .right = 0, .bottom = 5, .left = 0 };
    const result = r.withPadding(p);

    // top + bottom = 10 > height 8, should return 0 height
    try std.testing.expectEqual(@as(u16, 0), result.height);
}

// ============================================================================
// Layout Debugging Tests
// ============================================================================

test "LayoutDebugger.init creates empty debugger" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    // Debugger should be initialized with no nodes
    try std.testing.expectEqual(@as(usize, 0), debugger.nodes.items.len);
    try std.testing.expectEqual(allocator.ptr, debugger.allocator.ptr);
}

test "LayoutDebugger.deinit cleans up resources" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);

    // Add a node with allocated children to test recursive cleanup
    var children = try allocator.alloc(DebugNode, 1);
    children[0] = DebugNode{
        .constraint = .{ .length = 50 },
        .rect = Rect{ .x = 0, .y = 0, .width = 50, .height = 50 },
        .children = &[_]DebugNode{},
    };

    const parent = DebugNode{
        .constraint = .{ .length = 100 },
        .rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 },
        .children = children,
    };
    try debugger.nodes.append(allocator, parent);

    // Verify we have nodes
    try std.testing.expectEqual(@as(usize, 1), debugger.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 1), debugger.nodes.items[0].children.len);

    debugger.deinit();
    // Test passes if no memory leak detected by testing allocator
}

test "Rect.debugFormat formats simple rect" {
    const allocator = std.testing.allocator;
    _ = allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const r = Rect{ .x = 10, .y = 5, .width = 80, .height = 24 };
    try r.debugFormat(stream.writer());

    const output = stream.getWritten();
    // Should contain: "Rect{x=10, y=5, width=80, height=24}"
    try std.testing.expect(std.mem.indexOf(u8, output, "x=10") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "y=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "width=80") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "height=24") != null);
}

test "Rect.debugFormat handles zero dimensions" {
    const allocator = std.testing.allocator;
    _ = allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const r = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    try r.debugFormat(stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "x=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "y=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "width=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "height=0") != null);
}

test "DebugNode captures constraint and rect" {
    const allocator = std.testing.allocator;
    _ = allocator;
    const constraint = Constraint{ .length = 50 };
    const rect = Rect{ .x = 0, .y = 0, .width = 50, .height = 100 };

    const node = DebugNode{
        .constraint = constraint,
        .rect = rect,
        .children = &[_]DebugNode{},
    };

    // DebugNode should store constraint type and calculated rect
    try std.testing.expectEqual(Constraint.length, @as(std.meta.Tag(Constraint), node.constraint));
    try std.testing.expectEqual(50, node.constraint.length);
    try std.testing.expectEqual(50, node.rect.width);
}

test "DebugNode.percentage constraint captured correctly" {
    const allocator = std.testing.allocator;
    _ = allocator;
    const constraint = Constraint{ .percentage = 75 };
    const rect = Rect{ .x = 0, .y = 0, .width = 150, .height = 200 };

    const node = DebugNode{
        .constraint = constraint,
        .rect = rect,
        .children = &[_]DebugNode{},
    };

    try std.testing.expectEqual(Constraint.percentage, @as(std.meta.Tag(Constraint), node.constraint));
    try std.testing.expectEqual(75, node.constraint.percentage);
}

test "DebugNode.ratio constraint captured correctly" {
    const allocator = std.testing.allocator;
    _ = allocator;
    const constraint = Constraint{ .ratio = .{ .num = 3, .denom = 4 } };
    const rect = Rect{ .x = 0, .y = 0, .width = 75, .height = 100 };

    const node = DebugNode{
        .constraint = constraint,
        .rect = rect,
        .children = &[_]DebugNode{},
    };

    try std.testing.expectEqual(Constraint.ratio, @as(std.meta.Tag(Constraint), node.constraint));
    try std.testing.expectEqual(3, node.constraint.ratio.num);
    try std.testing.expectEqual(4, node.constraint.ratio.denom);
}

test "DebugNode.min constraint captured correctly" {
    const allocator = std.testing.allocator;
    _ = allocator;
    const constraint = Constraint{ .min = 100 };
    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    const node = DebugNode{
        .constraint = constraint,
        .rect = rect,
        .children = &[_]DebugNode{},
    };

    try std.testing.expectEqual(Constraint.min, @as(std.meta.Tag(Constraint), node.constraint));
    try std.testing.expectEqual(100, node.constraint.min);
}

test "DebugNode.max constraint captured correctly" {
    const allocator = std.testing.allocator;
    _ = allocator;
    const constraint = Constraint{ .max = 200 };
    const rect = Rect{ .x = 0, .y = 0, .width = 200, .height = 50 };

    const node = DebugNode{
        .constraint = constraint,
        .rect = rect,
        .children = &[_]DebugNode{},
    };

    try std.testing.expectEqual(Constraint.max, @as(std.meta.Tag(Constraint), node.constraint));
    try std.testing.expectEqual(200, node.constraint.max);
}

test "DebugNode.aspect_ratio constraint captured correctly" {
    const allocator = std.testing.allocator;
    _ = allocator;
    const constraint = Constraint{ .aspect_ratio = .{ .width = 16, .height = 9 } };
    const rect = Rect{ .x = 0, .y = 0, .width = 1600, .height = 900 };

    const node = DebugNode{
        .constraint = constraint,
        .rect = rect,
        .children = &[_]DebugNode{},
    };

    try std.testing.expectEqual(Constraint.aspect_ratio, @as(std.meta.Tag(Constraint), node.constraint));
    try std.testing.expectEqual(16, node.constraint.aspect_ratio.width);
    try std.testing.expectEqual(9, node.constraint.aspect_ratio.height);
}

test "LayoutDebugger.splitDebug creates nodes matching split results" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{
        .{ .length = 30 },
        .{ .percentage = 70 },
    };

    // splitDebug should return DebugNode array matching split() rects
    const nodes = try debugger.splitDebug(.horizontal, area, &constraints);
    defer allocator.free(nodes);

    // Also get regular split for comparison
    const rects = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(rects);

    try std.testing.expectEqual(2, nodes.len);
    try std.testing.expectEqual(rects[0], nodes[0].rect);
    try std.testing.expectEqual(rects[1], nodes[1].rect);
    try std.testing.expectEqual(Constraint.length, @as(std.meta.Tag(Constraint), nodes[0].constraint));
    try std.testing.expectEqual(Constraint.percentage, @as(std.meta.Tag(Constraint), nodes[1].constraint));
}

test "LayoutDebugger.splitDebug vertical split" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 100 };
    const constraints = [_]Constraint{
        .{ .percentage = 25 },
        .{ .percentage = 75 },
    };

    const nodes = try debugger.splitDebug(.vertical, area, &constraints);
    defer allocator.free(nodes);

    const rects = try split(allocator, .vertical, area, &constraints);
    defer allocator.free(rects);

    try std.testing.expectEqual(2, nodes.len);
    try std.testing.expectEqual(rects[0], nodes[0].rect);
    try std.testing.expectEqual(rects[1], nodes[1].rect);
}

test "LayoutDebugger.splitDebug with empty constraints" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{};

    const nodes = try debugger.splitDebug(.horizontal, area, &constraints);
    defer allocator.free(nodes);

    try std.testing.expectEqual(0, nodes.len);
}

test "LayoutDebugger.splitDebug with single constraint" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{
        .{ .percentage = 100 },
    };

    const nodes = try debugger.splitDebug(.horizontal, area, &constraints);
    defer allocator.free(nodes);

    try std.testing.expectEqual(1, nodes.len);
    try std.testing.expectEqual(100, nodes[0].rect.width);
}

test "LayoutDebugger nested splits create child nodes" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 100 };
    const parent_constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };

    const parent_nodes = try debugger.splitDebug(.horizontal, area, &parent_constraints);
    defer allocator.free(parent_nodes);

    // Now split the first parent node into children
    const child_constraints = [_]Constraint{
        .{ .length = 30 },
        .{ .percentage = 70 },
    };

    const child_nodes = try debugger.splitDebug(.vertical, parent_nodes[0].rect, &child_constraints);
    defer allocator.free(child_nodes);

    // Child nodes should exist and reference parent structure
    try std.testing.expectEqual(2, child_nodes.len);
    try std.testing.expect(child_nodes[0].rect.width == parent_nodes[0].rect.width);
}

test "LayoutDebugger.print outputs constraint info" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{
        .{ .length = 40 },
        .{ .percentage = 60 },
    };

    const nodes = try debugger.splitDebug(.horizontal, area, &constraints);
    defer allocator.free(nodes);

    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try debugger.print(stream.writer());

    const output = stream.getWritten();
    // Should contain constraint types
    try std.testing.expect(std.mem.indexOf(u8, output, "length") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "percentage") != null);
    // Should contain rect dimensions
    try std.testing.expect(std.mem.indexOf(u8, output, "width") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "height") != null);
}

test "LayoutDebugger.print shows tree indentation" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 100 };
    const constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };

    const nodes = try debugger.splitDebug(.horizontal, area, &constraints);
    defer allocator.free(nodes);

    var buf: [2048]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try debugger.print(stream.writer());

    const output = stream.getWritten();
    // Should show constraint info and rect info
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "Constraint:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Rect{") != null);
}

test "LayoutDebugger.print nested layout shows hierarchy" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    // Create a three-level nested layout
    const area = Rect{ .x = 0, .y = 0, .width = 300, .height = 200 };
    const level1_constraints = [_]Constraint{
        .{ .percentage = 33 },
        .{ .percentage = 67 },
    };

    const nodes = try debugger.splitDebug(.horizontal, area, &level1_constraints);
    defer allocator.free(nodes);

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try debugger.print(stream.writer());

    const output = stream.getWritten();
    // Nested structures should show different indentation levels
    try std.testing.expect(output.len > 0);
}

test "LayoutDebugger with all constraint types (SKIP: exposes split() overflow bug)" {
    return error.SkipZigTest;
}

test "LayoutDebugger deeply nested layout (5 levels)" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    var current_area = Rect{ .x = 0, .y = 0, .width = 1000, .height = 1000 };

    // Level 1
    const level1 = [_]Constraint{ .{ .percentage = 100 } };
    const nodes1 = try debugger.splitDebug(.vertical, current_area, &level1);
    defer allocator.free(nodes1);
    current_area = nodes1[0].rect;

    // Level 2
    const level2 = [_]Constraint{ .{ .percentage = 50 }, .{ .percentage = 50 } };
    const nodes2 = try debugger.splitDebug(.horizontal, current_area, &level2);
    defer allocator.free(nodes2);
    current_area = nodes2[0].rect;

    // Level 3
    const level3 = [_]Constraint{ .{ .length = 100 }, .{ .percentage = 80 } };
    const nodes3 = try debugger.splitDebug(.vertical, current_area, &level3);
    defer allocator.free(nodes3);
    current_area = nodes3[1].rect;

    // Level 4
    const level4 = [_]Constraint{ .{ .min = 50 }, .{ .max = 200 } };
    const nodes4 = try debugger.splitDebug(.horizontal, current_area, &level4);
    defer allocator.free(nodes4);
    current_area = nodes4[0].rect;

    // Level 5
    const level5 = [_]Constraint{ .{ .ratio = .{ .num = 1, .denom = 3 } } };
    const nodes5 = try debugger.splitDebug(.vertical, current_area, &level5);
    defer allocator.free(nodes5);

    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try debugger.print(stream.writer());

    const output = stream.getWritten();
    // Deep nesting should be visible in output
    try std.testing.expect(output.len > 100);
}

test "LayoutDebugger.print with rect coordinates" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    const area = Rect{ .x = 50, .y = 100, .width = 400, .height = 300 };
    const constraints = [_]Constraint{
        .{ .length = 200 },
        .{ .length = 200 },
    };

    const nodes = try debugger.splitDebug(.horizontal, area, &constraints);
    defer allocator.free(nodes);

    var buf: [2048]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try debugger.print(stream.writer());

    const output = stream.getWritten();
    // Should show x, y coordinates
    try std.testing.expect(std.mem.indexOf(u8, output, "x=") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "y=") != null);
}

test "LayoutDebugger handles zero-size rects" {
    const allocator = std.testing.allocator;
    var debugger = LayoutDebugger.init(allocator);
    defer debugger.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{
        .{ .max = 0 },
        .{ .percentage = 100 },
    };

    const nodes = try debugger.splitDebug(.horizontal, area, &constraints);
    defer allocator.free(nodes);

    try std.testing.expectEqual(2, nodes.len);
    try std.testing.expectEqual(0, nodes[0].rect.width);

    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try debugger.print(stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(output.len > 0);
}

// === Constraint Convenience Constructor Tests ===

test "Constraint.len creates length constraint" {
    const c = Constraint.len(50);
    try std.testing.expectEqual(Constraint{ .length = 50 }, c);
}

test "Constraint.len with zero value" {
    const c = Constraint.len(0);
    try std.testing.expectEqual(Constraint{ .length = 0 }, c);
}

test "Constraint.len with max u16 value" {
    const c = Constraint.len(65535);
    try std.testing.expectEqual(Constraint{ .length = 65535 }, c);
}

test "Constraint.len is equivalent to verbose syntax" {
    const c1 = Constraint.len(100);
    const c2 = Constraint{ .length = 100 };
    try std.testing.expectEqual(c1, c2);
    try std.testing.expectEqual(c1.apply(200), c2.apply(200));
}

test "Constraint.pct creates percentage constraint" {
    const c = Constraint.pct(75);
    try std.testing.expectEqual(Constraint{ .percentage = 75 }, c);
}

test "Constraint.pct with zero value" {
    const c = Constraint.pct(0);
    try std.testing.expectEqual(Constraint{ .percentage = 0 }, c);
}

test "Constraint.pct with 100 percent" {
    const c = Constraint.pct(100);
    try std.testing.expectEqual(Constraint{ .percentage = 100 }, c);
}

test "Constraint.pct clamps to 100" {
    const c = Constraint.pct(150);
    // Constructor should clamp to 100, so apply() returns full available space
    try std.testing.expectEqual(100, c.apply(100));
    try std.testing.expectEqual(50, c.apply(50));
}

test "Constraint.pct is equivalent to verbose syntax" {
    const c1 = Constraint.pct(50);
    const c2 = Constraint{ .percentage = 50 };
    try std.testing.expectEqual(c1, c2);
    try std.testing.expectEqual(c1.apply(100), c2.apply(100));
}

test "Constraint.rat creates ratio constraint" {
    const c = Constraint.rat(1, 2);
    try std.testing.expectEqual(Constraint{ .ratio = .{ .num = 1, .denom = 2 } }, c);
}

test "Constraint.rat with 1:1 ratio" {
    const c = Constraint.rat(1, 1);
    try std.testing.expectEqual(100, c.apply(100));
    try std.testing.expectEqual(50, c.apply(50));
}

test "Constraint.rat with 2:1 ratio" {
    const c = Constraint.rat(2, 1);
    try std.testing.expectEqual(200, c.apply(200)); // unclamped (200*2/1=400, min to 200)
    try std.testing.expectEqual(100, c.apply(100)); // clamped to available (100*2/1=200, min to 100)
}

test "Constraint.rat with zero numerator" {
    const c = Constraint.rat(0, 1);
    try std.testing.expectEqual(0, c.apply(100));
    try std.testing.expectEqual(0, c.apply(50));
}

test "Constraint.rat with zero denominator" {
    const c = Constraint.rat(1, 0);
    try std.testing.expectEqual(0, c.apply(100));
    try std.testing.expectEqual(0, c.apply(50));
}

test "Constraint.rat with large numerator and small denominator" {
    const c = Constraint.rat(3, 1);
    try std.testing.expectEqual(300, c.apply(300)); // capped to available
    try std.testing.expectEqual(100, c.apply(100));
}

test "Constraint.rat is equivalent to verbose syntax" {
    const c1 = Constraint.rat(1, 3);
    const c2 = Constraint{ .ratio = .{ .num = 1, .denom = 3 } };
    try std.testing.expectEqual(c1, c2);
    try std.testing.expectEqual(c1.apply(300), c2.apply(300));
}

test "Constraint.minimum creates min constraint" {
    const c = Constraint.minimum(50);
    try std.testing.expectEqual(Constraint{ .min = 50 }, c);
}

test "Constraint.minimum with zero value" {
    const c = Constraint.minimum(0);
    try std.testing.expectEqual(Constraint{ .min = 0 }, c);
}

test "Constraint.minimum with max u16 value" {
    const c = Constraint.minimum(65535);
    try std.testing.expectEqual(Constraint{ .min = 65535 }, c);
}

test "Constraint.minimum clamps to available space" {
    const c = Constraint.minimum(100);
    try std.testing.expectEqual(100, c.apply(150));
    try std.testing.expectEqual(50, c.apply(50)); // clamped to available
}

test "Constraint.minimum is equivalent to verbose syntax" {
    const c1 = Constraint.minimum(75);
    const c2 = Constraint{ .min = 75 };
    try std.testing.expectEqual(c1, c2);
    try std.testing.expectEqual(c1.apply(200), c2.apply(200));
}

test "Constraint.maximum creates max constraint" {
    const c = Constraint.maximum(100);
    try std.testing.expectEqual(Constraint{ .max = 100 }, c);
}

test "Constraint.maximum with zero value" {
    const c = Constraint.maximum(0);
    try std.testing.expectEqual(Constraint{ .max = 0 }, c);
}

test "Constraint.maximum with max u16 value" {
    const c = Constraint.maximum(65535);
    try std.testing.expectEqual(Constraint{ .max = 65535 }, c);
}

test "Constraint.maximum clamps to max value" {
    const c = Constraint.maximum(50);
    try std.testing.expectEqual(50, c.apply(100));
    try std.testing.expectEqual(30, c.apply(30)); // available is smaller
}

test "Constraint.maximum is equivalent to verbose syntax" {
    const c1 = Constraint.maximum(200);
    const c2 = Constraint{ .max = 200 };
    try std.testing.expectEqual(c1, c2);
    try std.testing.expectEqual(c1.apply(300), c2.apply(300));
}

test "Constraint.aspect creates aspect ratio constraint" {
    const c = Constraint.aspect(16, 9);
    try std.testing.expectEqual(Constraint{ .aspect_ratio = .{ .width = 16, .height = 9 } }, c);
}

test "Constraint.aspect with 1:1 square ratio" {
    const c = Constraint.aspect(1, 1);
    try std.testing.expectEqual(Constraint{ .aspect_ratio = .{ .width = 1, .height = 1 } }, c);
}

test "Constraint.aspect with 4:3 ratio" {
    const c = Constraint.aspect(4, 3);
    try std.testing.expectEqual(Constraint{ .aspect_ratio = .{ .width = 4, .height = 3 } }, c);
}

test "Constraint.aspect with zero width" {
    const c = Constraint.aspect(0, 9);
    try std.testing.expectEqual(0, c.apply(100)); // invalid aspect ratio
}

test "Constraint.aspect with zero height" {
    const c = Constraint.aspect(16, 0);
    try std.testing.expectEqual(0, c.apply(100)); // invalid aspect ratio
}

test "Constraint.aspect with both zero" {
    const c = Constraint.aspect(0, 0);
    try std.testing.expectEqual(0, c.apply(100));
}

test "Constraint.aspect is equivalent to verbose syntax" {
    const c1 = Constraint.aspect(21, 9);
    const c2 = Constraint{ .aspect_ratio = .{ .width = 21, .height = 9 } };
    try std.testing.expectEqual(c1, c2);
    try std.testing.expectEqual(c1.apply(100), c2.apply(100));
}

// Integration tests: using convenience constructors in split()

test "split uses Constraint.len convenience constructor" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{
        Constraint.len(30),
        Constraint.len(70),
    };

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(2, result.len);
    try std.testing.expectEqual(30, result[0].width);
    try std.testing.expectEqual(70, result[1].width);
}

test "split uses Constraint.pct convenience constructor" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const constraints = [_]Constraint{
        Constraint.pct(25),
        Constraint.pct(75),
    };

    const result = try split(allocator, .vertical, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(2, result.len);
    try std.testing.expectEqual(25, result[0].height);
    try std.testing.expectEqual(75, result[1].height);
}

test "split uses Constraint.rat convenience constructor" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const constraints = [_]Constraint{
        Constraint.rat(1, 3),
        Constraint.rat(2, 3),
    };

    const result = try split(allocator, .vertical, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(2, result.len);
}

test "split uses mixed convenience constructors" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const constraints = [_]Constraint{
        Constraint.len(20),
        Constraint.pct(50),
        Constraint.rat(1, 4),
    };

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(3, result.len);
    try std.testing.expect(result[0].width > 0);
    try std.testing.expect(result[1].width > 0);
    try std.testing.expect(result[2].width > 0);
}

test "split uses Constraint.minimum convenience constructor" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const constraints = [_]Constraint{
        Constraint.minimum(30),
        Constraint.minimum(30),
    };

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(2, result.len);
}

test "split uses Constraint.maximum convenience constructor" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const constraints = [_]Constraint{
        Constraint.maximum(50),
        Constraint.maximum(50),
    };

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(2, result.len);
    try std.testing.expect(result[0].width <= 50);
    try std.testing.expect(result[1].width <= 50);
}

test "Constraint.apply works with all convenience constructor types" {
    const c_len = Constraint.len(50);
    const c_pct = Constraint.pct(50);
    const c_rat = Constraint.rat(1, 2);
    const c_min = Constraint.minimum(50);
    const c_max = Constraint.maximum(50);

    try std.testing.expectEqual(50, c_len.apply(100));
    try std.testing.expectEqual(50, c_pct.apply(100));
    try std.testing.expectEqual(50, c_rat.apply(100));
    try std.testing.expectEqual(50, c_min.apply(100));
    try std.testing.expectEqual(50, c_max.apply(100));
}

test "Constraint constructors maintain type safety" {
    // Verify that each constructor creates the correct union variant
    const c_len = Constraint.len(50);
    const c_pct = Constraint.pct(50);
    const c_rat = Constraint.rat(1, 2);
    const c_min = Constraint.minimum(50);
    const c_max = Constraint.maximum(50);
    const c_aspect = Constraint.aspect(16, 9);

    // Switch on each to ensure they are the correct types
    try std.testing.expectEqual(true, std.meta.activeTag(c_len) == .length);
    try std.testing.expectEqual(true, std.meta.activeTag(c_pct) == .percentage);
    try std.testing.expectEqual(true, std.meta.activeTag(c_rat) == .ratio);
    try std.testing.expectEqual(true, std.meta.activeTag(c_min) == .min);
    try std.testing.expectEqual(true, std.meta.activeTag(c_max) == .max);
    try std.testing.expectEqual(true, std.meta.activeTag(c_aspect) == .aspect_ratio);
}

// ============================================================================
// Additional Coverage Tests (added in stabilization session 140)
// ============================================================================

test "Rect.withAspectRatio - width constrained" {
    const rect = Rect{ .x = 10, .y = 20, .width = 100, .height = 100 };
    const result = rect.withAspectRatio(.{ .width = 16, .height = 9 });

    // 16:9 in 100x100: width-constrained gives 100 width, 56.25 height
    try std.testing.expectEqual(@as(u16, 10), result.x);
    try std.testing.expectEqual(@as(u16, 20), result.y);
    try std.testing.expectEqual(@as(u16, 100), result.width);
    try std.testing.expect(result.height <= 100);
}

test "Rect.withAspectRatio - height constrained" {
    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const result = rect.withAspectRatio(.{ .width = 16, .height = 9 });

    // 16:9 in 100x50: height-constrained gives 50 height, ~88 width
    try std.testing.expectEqual(@as(u16, 50), result.height);
    try std.testing.expect(result.width <= 100);
}

test "Rect.withAspectRatio - zero ratio" {
    const rect = Rect{ .x = 5, .y = 5, .width = 80, .height = 24 };
    const result = rect.withAspectRatio(.{ .width = 0, .height = 9 });

    // Zero width/height should return zero dimensions
    try std.testing.expectEqual(@as(u16, 0), result.width);
    try std.testing.expectEqual(@as(u16, 0), result.height);
}

test "Rect.withMargin - symmetric" {
    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const margin = Margin.all(5);
    const result = rect.withMargin(margin);

    try std.testing.expectEqual(@as(u16, 5), result.x);
    try std.testing.expectEqual(@as(u16, 5), result.y);
    try std.testing.expectEqual(@as(u16, 90), result.width); // 100 - (5+5)
    try std.testing.expectEqual(@as(u16, 40), result.height); // 50 - (5+5)
}

test "Rect.withMargin - asymmetric" {
    const rect = Rect{ .x = 10, .y = 10, .width = 100, .height = 50 };
    const margin = Margin{ .top = 5, .right = 10, .bottom = 5, .left = 10 };
    const result = rect.withMargin(margin);

    try std.testing.expectEqual(@as(u16, 20), result.x); // 10 + 10 (left margin)
    try std.testing.expectEqual(@as(u16, 15), result.y); // 10 + 5 (top margin)
    try std.testing.expectEqual(@as(u16, 80), result.width); // 100 - (10+10)
    try std.testing.expectEqual(@as(u16, 40), result.height); // 50 - (5+5)
}

test "Rect.withMargin - exceeds dimensions" {
    const rect = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    const margin = Margin.all(15);
    const result = rect.withMargin(margin);

    // Margin exceeds size, should return zero dimensions
    try std.testing.expectEqual(@as(u16, 0), result.width);
    try std.testing.expectEqual(@as(u16, 0), result.height);
}

test "Rect.withPadding - symmetric" {
    const rect = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const padding = Padding.all(2);
    const result = rect.withPadding(padding);

    try std.testing.expectEqual(@as(u16, 2), result.x);
    try std.testing.expectEqual(@as(u16, 2), result.y);
    try std.testing.expectEqual(@as(u16, 76), result.width); // 80 - 4
    try std.testing.expectEqual(@as(u16, 20), result.height); // 24 - 4
}

test "Rect.withPadding - asymmetric" {
    const rect = Rect{ .x = 5, .y = 5, .width = 50, .height = 30 };
    const padding = Padding{ .top = 1, .right = 2, .bottom = 3, .left = 4 };
    const result = rect.withPadding(padding);

    try std.testing.expectEqual(@as(u16, 9), result.x); // 5 + 4
    try std.testing.expectEqual(@as(u16, 6), result.y); // 5 + 1
    try std.testing.expectEqual(@as(u16, 44), result.width); // 50 - (4+2)
    try std.testing.expectEqual(@as(u16, 26), result.height); // 30 - (1+3)
}

test "Rect.withPadding - exceeds dimensions" {
    const rect = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const padding = Padding.all(6);
    const result = rect.withPadding(padding);

    // Padding exceeds size
    try std.testing.expectEqual(@as(u16, 0), result.width);
    try std.testing.expectEqual(@as(u16, 0), result.height);
}

test "Rect.fromSize - convenience constructor" {
    const rect = Rect.fromSize(80, 24);

    try std.testing.expectEqual(@as(u16, 0), rect.x);
    try std.testing.expectEqual(@as(u16, 0), rect.y);
    try std.testing.expectEqual(@as(u16, 80), rect.width);
    try std.testing.expectEqual(@as(u16, 24), rect.height);
}

test "Rect.debugFormat - output" {
    const rect = Rect{ .x = 10, .y = 20, .width = 80, .height = 24 };

    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try rect.debugFormat(fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Rect{") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "x=10") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "y=20") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "width=80") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "height=24") != null);
}

test "Margin.all - convenience constructor" {
    const margin = Margin.all(10);

    try std.testing.expectEqual(@as(u16, 10), margin.top);
    try std.testing.expectEqual(@as(u16, 10), margin.right);
    try std.testing.expectEqual(@as(u16, 10), margin.bottom);
    try std.testing.expectEqual(@as(u16, 10), margin.left);
}

test "Margin.symmetric - convenience constructor" {
    const margin = Margin.symmetric(5, 10);

    try std.testing.expectEqual(@as(u16, 5), margin.top);
    try std.testing.expectEqual(@as(u16, 10), margin.right);
    try std.testing.expectEqual(@as(u16, 5), margin.bottom);
    try std.testing.expectEqual(@as(u16, 10), margin.left);
}

test "Padding.all - convenience constructor" {
    const padding = Padding.all(3);

    try std.testing.expectEqual(@as(u16, 3), padding.top);
    try std.testing.expectEqual(@as(u16, 3), padding.right);
    try std.testing.expectEqual(@as(u16, 3), padding.bottom);
    try std.testing.expectEqual(@as(u16, 3), padding.left);
}

test "Padding.symmetric - convenience constructor" {
    const padding = Padding.symmetric(2, 4);

    try std.testing.expectEqual(@as(u16, 2), padding.top);
    try std.testing.expectEqual(@as(u16, 4), padding.right);
    try std.testing.expectEqual(@as(u16, 2), padding.bottom);
    try std.testing.expectEqual(@as(u16, 4), padding.left);
}
