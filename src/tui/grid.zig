const std = @import("std");
const Allocator = std.mem.Allocator;
const layout = @import("layout.zig");
const Rect = layout.Rect;
const Constraint = layout.Constraint;

/// Grid track size (row/column)
pub const Track = union(enum) {
    /// Fixed size in cells
    fixed: u16,
    /// Fraction of remaining space
    fr: u32,
    /// Auto-sized to content
    auto,
    /// Minimum of two sizes
    min_content,
    /// Maximum of two sizes
    max_content,

    /// Calculate actual size for this track
    pub fn apply(self: Track, available: u16, content_size: u16) u16 {
        return switch (self) {
            .fixed => |size| @min(size, available),
            .auto, .min_content => @min(content_size, available),
            .max_content => @min(content_size, available),
            .fr => 0, // Handled separately in grid solver
        };
    }
};

/// Grid alignment options
pub const Align = enum {
    start,
    end_,
    center,
    stretch,
};

/// Grid item placement
pub const GridItem = struct {
    /// Row start (1-indexed)
    row: u16,
    /// Column start (1-indexed)
    col: u16,
    /// Row span (default 1)
    row_span: u16 = 1,
    /// Column span (default 1)
    col_span: u16 = 1,
    /// Horizontal alignment
    h_align: Align = .stretch,
    /// Vertical alignment
    v_align: Align = .stretch,
};

/// Grid configuration
pub const Grid = struct {
    /// Row tracks
    rows: []const Track,
    /// Column tracks
    cols: []const Track,
    /// Gap between rows
    row_gap: u16 = 0,
    /// Gap between columns
    col_gap: u16 = 0,

    /// Layout items in a grid
    pub fn layout(
        self: Grid,
        allocator: Allocator,
        area: Rect,
        items: []const GridItem,
    ) ![]Rect {
        if (items.len == 0) return &[_]Rect{};

        // Allocate result
        const result = try allocator.alloc(Rect, items.len);
        errdefer allocator.free(result);

        // Calculate row heights
        const row_heights = try self.calculateTracks(
            allocator,
            area.height,
            self.rows,
            self.row_gap,
        );
        defer allocator.free(row_heights);

        // Calculate column widths
        const col_widths = try self.calculateTracks(
            allocator,
            area.width,
            self.cols,
            self.col_gap,
        );
        defer allocator.free(col_widths);

        // Calculate row positions
        const row_positions = try self.calculatePositions(
            allocator,
            area.y,
            row_heights,
            self.row_gap,
        );
        defer allocator.free(row_positions);

        // Calculate column positions
        const col_positions = try self.calculatePositions(
            allocator,
            area.x,
            col_widths,
            self.col_gap,
        );
        defer allocator.free(col_positions);

        // Position each item
        for (items, 0..) |item, i| {
            const row_idx = if (item.row > 0) item.row - 1 else 0;
            const col_idx = if (item.col > 0) item.col - 1 else 0;

            // Bounds check
            if (row_idx >= self.rows.len or col_idx >= self.cols.len) {
                result[i] = Rect.new(0, 0, 0, 0);
                continue;
            }

            // Calculate cell area
            const x = col_positions[col_idx];
            const y = row_positions[row_idx];

            // Calculate width (with span)
            var width: u16 = col_widths[col_idx];
            if (item.col_span > 1) {
                var span_idx: u16 = 1;
                while (span_idx < item.col_span and col_idx + span_idx < self.cols.len) : (span_idx += 1) {
                    width += self.col_gap + col_widths[col_idx + span_idx];
                }
            }

            // Calculate height (with span)
            var height: u16 = row_heights[row_idx];
            if (item.row_span > 1) {
                var span_idx: u16 = 1;
                while (span_idx < item.row_span and row_idx + span_idx < self.rows.len) : (span_idx += 1) {
                    height += self.row_gap + row_heights[row_idx + span_idx];
                }
            }

            // Apply alignment
            var final_x = x;
            var final_y = y;
            var final_width = width;
            var final_height = height;

            switch (item.h_align) {
                .start => {},
                .end_ => final_x = x + width - final_width,
                .center => final_x = x + (width - final_width) / 2,
                .stretch => final_width = width,
            }

            switch (item.v_align) {
                .start => {},
                .end_ => final_y = y + height - final_height,
                .center => final_y = y + (height - final_height) / 2,
                .stretch => final_height = height,
            }

            result[i] = Rect.new(final_x, final_y, final_width, final_height);
        }

        return result;
    }

    fn calculateTracks(
        _: Grid,
        allocator: Allocator,
        available: u16,
        tracks: []const Track,
        gap: u16,
    ) ![]u16 {
        const sizes = try allocator.alloc(u16, tracks.len);
        errdefer allocator.free(sizes);

        // Account for gaps
        const total_gap = if (tracks.len > 1) gap * @as(u16, @intCast(tracks.len - 1)) else 0;
        const available_for_tracks = if (available > total_gap) available - total_gap else 0;

        // First pass: calculate fixed and auto sizes
        var fixed_total: u32 = 0;
        var fr_total: u32 = 0;

        for (tracks, 0..) |track, i| {
            switch (track) {
                .fixed => |size| {
                    sizes[i] = @min(size, available_for_tracks);
                    fixed_total += sizes[i];
                },
                .fr => |fr| {
                    sizes[i] = 0;
                    fr_total += fr;
                },
                else => {
                    // Auto and others: default to equal distribution
                    sizes[i] = 0;
                },
            }
        }

        // Calculate remaining space for fr tracks
        const remaining = if (available_for_tracks > fixed_total)
            available_for_tracks - @as(u16, @intCast(fixed_total))
        else
            0;

        // Distribute remaining space to fr tracks
        if (fr_total > 0) {
            for (tracks, 0..) |track, i| {
                if (track == .fr) {
                    const fr_unit = @as(u32, remaining) / fr_total;
                    sizes[i] = @as(u16, @intCast(@min(fr_unit * track.fr, remaining)));
                }
            }
        } else if (remaining > 0) {
            // Distribute remaining to auto tracks
            var auto_count: u16 = 0;
            for (tracks) |track| {
                if (track == .auto or track == .min_content or track == .max_content) {
                    auto_count += 1;
                }
            }
            if (auto_count > 0) {
                const per_auto = remaining / auto_count;
                for (tracks, 0..) |track, i| {
                    if (track == .auto or track == .min_content or track == .max_content) {
                        sizes[i] = per_auto;
                    }
                }
            }
        }

        return sizes;
    }

    fn calculatePositions(
        _: Grid,
        allocator: Allocator,
        start: u16,
        sizes: []const u16,
        gap: u16,
    ) ![]u16 {
        const positions = try allocator.alloc(u16, sizes.len);
        errdefer allocator.free(positions);

        var offset: u16 = start;
        for (sizes, 0..) |size, i| {
            positions[i] = offset;
            offset += size + gap;
        }

        return positions;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Track.fixed" {
    const track = Track{ .fixed = 50 };
    try std.testing.expectEqual(50, track.apply(100, 30));
    try std.testing.expectEqual(40, track.apply(40, 30)); // clamped to available
}

test "Track.auto" {
    const track: Track = .auto;
    try std.testing.expectEqual(30, track.apply(100, 30));
    try std.testing.expectEqual(20, track.apply(20, 30)); // clamped to available
}

test "Track.fr" {
    const track = Track{ .fr = 1 };
    try std.testing.expectEqual(0, track.apply(100, 30)); // handled separately
}

test "Grid.layout - simple 2x2" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 25 }, .{ .fixed = 25 } },
        .cols = &[_]Track{ .{ .fixed = 40 }, .{ .fixed = 40 } },
    };

    const area = Rect.new(0, 0, 80, 50);
    const items = [_]GridItem{
        .{ .row = 1, .col = 1 },
        .{ .row = 1, .col = 2 },
        .{ .row = 2, .col = 1 },
        .{ .row = 2, .col = 2 },
    };

    const result = try grid.layout(allocator, area, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(4, result.len);

    // Top-left
    try std.testing.expectEqual(0, result[0].x);
    try std.testing.expectEqual(0, result[0].y);
    try std.testing.expectEqual(40, result[0].width);
    try std.testing.expectEqual(25, result[0].height);

    // Top-right
    try std.testing.expectEqual(40, result[1].x);
    try std.testing.expectEqual(0, result[1].y);
}

test "Grid.layout - with gaps" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 25 }, .{ .fixed = 25 } },
        .cols = &[_]Track{ .{ .fixed = 40 }, .{ .fixed = 40 } },
        .row_gap = 5,
        .col_gap = 10,
    };

    const area = Rect.new(0, 0, 90, 55);
    const items = [_]GridItem{
        .{ .row = 1, .col = 1 },
        .{ .row = 1, .col = 2 },
        .{ .row = 2, .col = 1 },
        .{ .row = 2, .col = 2 },
    };

    const result = try grid.layout(allocator, area, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(4, result.len);

    // Top-left
    try std.testing.expectEqual(0, result[0].x);
    try std.testing.expectEqual(0, result[0].y);

    // Top-right (shifted by column gap)
    try std.testing.expectEqual(50, result[1].x); // 40 + 10 gap
    try std.testing.expectEqual(0, result[1].y);

    // Bottom-left (shifted by row gap)
    try std.testing.expectEqual(0, result[2].x);
    try std.testing.expectEqual(30, result[2].y); // 25 + 5 gap
}

test "Grid.layout - column span" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 25 }, .{ .fixed = 25 } },
        .cols = &[_]Track{ .{ .fixed = 30 }, .{ .fixed = 30 }, .{ .fixed = 30 } },
        .col_gap = 5,
    };

    const area = Rect.new(0, 0, 100, 50);
    const items = [_]GridItem{
        .{ .row = 1, .col = 1, .col_span = 2 }, // spans 2 columns
        .{ .row = 1, .col = 3 },
        .{ .row = 2, .col = 1 },
        .{ .row = 2, .col = 2 },
        .{ .row = 2, .col = 3 },
    };

    const result = try grid.layout(allocator, area, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(5, result.len);

    // First item spans 2 columns: 30 + 5 (gap) + 30 = 65
    try std.testing.expectEqual(65, result[0].width);
}

test "Grid.layout - row span" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 20 }, .{ .fixed = 20 }, .{ .fixed = 20 } },
        .cols = &[_]Track{ .{ .fixed = 40 }, .{ .fixed = 40 } },
        .row_gap = 5,
    };

    const area = Rect.new(0, 0, 80, 65);
    const items = [_]GridItem{
        .{ .row = 1, .col = 1, .row_span = 2 }, // spans 2 rows
        .{ .row = 1, .col = 2 },
        .{ .row = 2, .col = 2 },
        .{ .row = 3, .col = 1 },
        .{ .row = 3, .col = 2 },
    };

    const result = try grid.layout(allocator, area, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(5, result.len);

    // First item spans 2 rows: 20 + 5 (gap) + 20 = 45
    try std.testing.expectEqual(45, result[0].height);
}

test "Grid.layout - fr units" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 25 } },
        .cols = &[_]Track{ .{ .fr = 1 }, .{ .fr = 2 }, .{ .fr = 1 } },
    };

    const area = Rect.new(0, 0, 100, 50);
    const items = [_]GridItem{
        .{ .row = 1, .col = 1 },
        .{ .row = 1, .col = 2 },
        .{ .row = 1, .col = 3 },
    };

    const result = try grid.layout(allocator, area, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(3, result.len);

    // Total fr: 4, available: 100
    // Each fr unit: 100/4 = 25
    // Col 1: 1fr = 25, Col 2: 2fr = 50, Col 3: 1fr = 25
    try std.testing.expectEqual(25, result[0].width);
    try std.testing.expectEqual(50, result[1].width);
    try std.testing.expectEqual(25, result[2].width);
}

test "Grid.layout - alignment center" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 50 } },
        .cols = &[_]Track{ .{ .fixed = 100 } },
    };

    const area = Rect.new(0, 0, 100, 50);
    const items = [_]GridItem{
        .{ .row = 1, .col = 1, .h_align = .center, .v_align = .center },
    };

    const result = try grid.layout(allocator, area, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(1, result.len);
    // With center alignment, item should be centered in cell
    // Since item size = cell size, position should be 0,0
    try std.testing.expectEqual(0, result[0].x);
    try std.testing.expectEqual(0, result[0].y);
}

test "Grid.layout - empty items" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 25 } },
        .cols = &[_]Track{ .{ .fixed = 40 } },
    };

    const area = Rect.new(0, 0, 100, 50);
    const items = [_]GridItem{};

    const result = try grid.layout(allocator, area, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(0, result.len);
}

test "Grid.layout - out of bounds item" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 25 } },
        .cols = &[_]Track{ .{ .fixed = 40 } },
    };

    const area = Rect.new(0, 0, 100, 50);
    const items = [_]GridItem{
        .{ .row = 5, .col = 5 }, // out of bounds
    };

    const result = try grid.layout(allocator, area, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(1, result.len);
    // Out of bounds items get zero rect
    try std.testing.expectEqual(0, result[0].width);
    try std.testing.expectEqual(0, result[0].height);
}

test "Grid.layout - mixed track types" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 25 }, .auto },
        .cols = &[_]Track{ .{ .fixed = 30 }, .{ .fr = 1 } },
    };

    const area = Rect.new(0, 0, 100, 50);
    const items = [_]GridItem{
        .{ .row = 1, .col = 1 },
        .{ .row = 1, .col = 2 },
        .{ .row = 2, .col = 1 },
        .{ .row = 2, .col = 2 },
    };

    const result = try grid.layout(allocator, area, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(4, result.len);

    // First column is fixed at 30
    try std.testing.expectEqual(30, result[0].width);
    // Second column gets remaining space (100 - 30 = 70)
    try std.testing.expectEqual(70, result[1].width);
}

test "Grid.layout - single cell" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 50 } },
        .cols = &[_]Track{ .{ .fixed = 100 } },
    };

    const area = Rect.new(10, 20, 100, 50);
    const items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const result = try grid.layout(allocator, area, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(1, result.len);
    try std.testing.expectEqual(10, result[0].x);
    try std.testing.expectEqual(20, result[0].y);
    try std.testing.expectEqual(100, result[0].width);
    try std.testing.expectEqual(50, result[0].height);
}

test "Grid.calculateTracks - all fixed" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{},
        .cols = &[_]Track{ .{ .fixed = 30 }, .{ .fixed = 40 }, .{ .fixed = 30 } },
    };

    const sizes = try grid.calculateTracks(allocator, 100, grid.cols, 0);
    defer allocator.free(sizes);

    try std.testing.expectEqual(3, sizes.len);
    try std.testing.expectEqual(30, sizes[0]);
    try std.testing.expectEqual(40, sizes[1]);
    try std.testing.expectEqual(30, sizes[2]);
}

test "Grid.calculateTracks - with gaps" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{},
        .cols = &[_]Track{ .{ .fixed = 30 }, .{ .fixed = 30 } },
        .col_gap = 10,
    };

    const sizes = try grid.calculateTracks(allocator, 70, grid.cols, grid.col_gap);
    defer allocator.free(sizes);

    // Available: 70, Gap: 10, Remaining: 60
    // Each column: 30
    try std.testing.expectEqual(2, sizes.len);
    try std.testing.expectEqual(30, sizes[0]);
    try std.testing.expectEqual(30, sizes[1]);
}

test "Grid.calculatePositions" {
    const allocator = std.testing.allocator;

    const grid = Grid{
        .rows = &[_]Track{},
        .cols = &[_]Track{},
    };

    const sizes = [_]u16{ 30, 40, 30 };
    const positions = try grid.calculatePositions(allocator, 10, &sizes, 5);
    defer allocator.free(positions);

    try std.testing.expectEqual(3, positions.len);
    try std.testing.expectEqual(10, positions[0]); // 10
    try std.testing.expectEqual(45, positions[1]); // 10 + 30 + 5
    try std.testing.expectEqual(90, positions[2]); // 45 + 40 + 5
}
