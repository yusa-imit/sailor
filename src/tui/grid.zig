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
                result[i] = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
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

            result[i] = Rect{ .x = final_x, .y = final_y, .width = final_width, .height = final_height };
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

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 50 };
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

    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 55 };
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

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
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

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 65 };
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

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
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

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
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

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
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

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
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

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
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

    const area = Rect{ .x = 10, .y = 20, .width = 100, .height = 50 };
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

// ============================================================================
// Nested Grid Tests
// ============================================================================

test "nested grid - basic 2x2 outer with 2x2 inner" {
    const allocator = std.testing.allocator;

    // Outer 2x2 grid
    const outer_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 50 }, .{ .fixed = 50 } },
        .cols = &[_]Track{ .{ .fixed = 50 }, .{ .fixed = 50 } },
    };

    const outer_area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const outer_items = [_]GridItem{
        .{ .row = 1, .col = 1 }, // Will contain inner grid
        .{ .row = 1, .col = 2 },
        .{ .row = 2, .col = 1 },
        .{ .row = 2, .col = 2 },
    };

    const outer_result = try outer_grid.layout(allocator, outer_area, &outer_items);
    defer allocator.free(outer_result);

    try std.testing.expectEqual(4, outer_result.len);

    // Cell [0,0] (top-left) has rect (0, 0, 50, 50)
    const nested_cell = outer_result[0];
    try std.testing.expectEqual(0, nested_cell.x);
    try std.testing.expectEqual(0, nested_cell.y);
    try std.testing.expectEqual(50, nested_cell.width);
    try std.testing.expectEqual(50, nested_cell.height);

    // Layout inner 2x2 grid in the cell's rect
    const inner_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 25 }, .{ .fixed = 25 } },
        .cols = &[_]Track{ .{ .fixed = 25 }, .{ .fixed = 25 } },
    };

    const inner_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
        .{ .row = 1, .col = 2 },
        .{ .row = 2, .col = 1 },
        .{ .row = 2, .col = 2 },
    };

    const inner_result = try inner_grid.layout(allocator, nested_cell, &inner_items);
    defer allocator.free(inner_result);

    try std.testing.expectEqual(4, inner_result.len);

    // Verify inner grid fills the parent cell
    // Inner cell [0,0] should be at absolute position (0, 0)
    try std.testing.expectEqual(0, inner_result[0].x);
    try std.testing.expectEqual(0, inner_result[0].y);
    try std.testing.expectEqual(25, inner_result[0].width);
    try std.testing.expectEqual(25, inner_result[0].height);

    // Inner cell [0,1] should be at absolute position (25, 0)
    try std.testing.expectEqual(25, inner_result[1].x);
    try std.testing.expectEqual(0, inner_result[1].y);

    // Inner cell [1,0] should be at absolute position (0, 25)
    try std.testing.expectEqual(0, inner_result[2].x);
    try std.testing.expectEqual(25, inner_result[2].y);
}

test "nested grid - auto-sizing inner grid content" {
    const allocator = std.testing.allocator;

    // Outer grid with flexible track
    const outer_grid = Grid{
        .rows = &[_]Track{ .{ .fr = 1 } },
        .cols = &[_]Track{ .{ .fr = 1 } },
    };

    const outer_area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const outer_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const outer_result = try outer_grid.layout(allocator, outer_area, &outer_items);
    defer allocator.free(outer_result);

    // Cell should fill the entire area
    const nested_cell = outer_result[0];
    try std.testing.expectEqual(100, nested_cell.width);
    try std.testing.expectEqual(100, nested_cell.height);

    // Inner grid with auto tracks should fill the cell
    const inner_grid = Grid{
        .rows = &[_]Track{ .auto, .auto },
        .cols = &[_]Track{ .auto, .auto },
    };

    const inner_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
        .{ .row = 1, .col = 2 },
        .{ .row = 2, .col = 1 },
        .{ .row = 2, .col = 2 },
    };

    const inner_result = try inner_grid.layout(allocator, nested_cell, &inner_items);
    defer allocator.free(inner_result);

    // Auto tracks should distribute space equally
    // 100 / 2 = 50 per column
    try std.testing.expectEqual(50, inner_result[0].width);
    try std.testing.expectEqual(50, inner_result[0].height);
    try std.testing.expectEqual(50, inner_result[1].width);
    try std.testing.expectEqual(50, inner_result[2].height);
}

test "nested grid - multiple nested grids in different cells" {
    const allocator = std.testing.allocator;

    // Outer 2x2 grid
    const outer_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 60 }, .{ .fixed = 60 } },
        .cols = &[_]Track{ .{ .fixed = 60 }, .{ .fixed = 60 } },
        .col_gap = 10,
        .row_gap = 10,
    };

    const outer_area = Rect{ .x = 0, .y = 0, .width = 130, .height = 130 };
    const outer_items = [_]GridItem{
        .{ .row = 1, .col = 1 }, // Top-left: will have nested grid
        .{ .row = 1, .col = 2 }, // Top-right: will have different nested grid
        .{ .row = 2, .col = 1 }, // Bottom-left: regular item
        .{ .row = 2, .col = 2 }, // Bottom-right: will have another nested grid
    };

    const outer_result = try outer_grid.layout(allocator, outer_area, &outer_items);
    defer allocator.free(outer_result);

    try std.testing.expectEqual(4, outer_result.len);

    // Verify positions with gaps
    // Cell [0,0]: (0, 0, 60, 60)
    try std.testing.expectEqual(0, outer_result[0].x);
    try std.testing.expectEqual(0, outer_result[0].y);
    try std.testing.expectEqual(60, outer_result[0].width);
    try std.testing.expectEqual(60, outer_result[0].height);

    // Cell [0,1]: (70, 0, 60, 60) — shifted by col_gap
    try std.testing.expectEqual(70, outer_result[1].x);
    try std.testing.expectEqual(0, outer_result[1].y);

    // Cell [1,0]: (0, 70, 60, 60) — shifted by row_gap
    try std.testing.expectEqual(0, outer_result[2].x);
    try std.testing.expectEqual(70, outer_result[2].y);

    // Cell [1,1]: (70, 70, 60, 60)
    try std.testing.expectEqual(70, outer_result[3].x);
    try std.testing.expectEqual(70, outer_result[3].y);

    // Layout nested grid in top-left cell
    const inner_grid_tl = Grid{
        .rows = &[_]Track{ .{ .fixed = 30 } },
        .cols = &[_]Track{ .{ .fixed = 30 } },
    };

    const inner_items_tl = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const inner_result_tl = try inner_grid_tl.layout(allocator, outer_result[0], &inner_items_tl);
    defer allocator.free(inner_result_tl);

    // Top-left nested grid cell should be within the parent cell bounds
    try std.testing.expectEqual(30, inner_result_tl[0].width);
    try std.testing.expectEqual(30, inner_result_tl[0].height);

    // Layout different nested grid in top-right cell
    const inner_grid_tr = Grid{
        .rows = &[_]Track{ .{ .fixed = 20 }, .{ .fixed = 20 } },
        .cols = &[_]Track{ .{ .fixed = 20 }, .{ .fixed = 20 } },
    };

    const inner_items_tr = [_]GridItem{
        .{ .row = 1, .col = 1 },
        .{ .row = 1, .col = 2 },
        .{ .row = 2, .col = 1 },
        .{ .row = 2, .col = 2 },
    };

    const inner_result_tr = try inner_grid_tr.layout(allocator, outer_result[1], &inner_items_tr);
    defer allocator.free(inner_result_tr);

    try std.testing.expectEqual(4, inner_result_tr.len);
    try std.testing.expectEqual(20, inner_result_tr[0].width);
    try std.testing.expectEqual(20, inner_result_tr[1].width);
}

test "nested grid - deep nesting (3 levels)" {
    const allocator = std.testing.allocator;

    // Level 1: Outer grid (1x1)
    const level1_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 100 } },
        .cols = &[_]Track{ .{ .fixed = 100 } },
    };

    const level1_area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const level1_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const level1_result = try level1_grid.layout(allocator, level1_area, &level1_items);
    defer allocator.free(level1_result);

    const level1_cell = level1_result[0];
    try std.testing.expectEqual(100, level1_cell.width);
    try std.testing.expectEqual(100, level1_cell.height);

    // Level 2: Middle grid (1x1) inside Level 1's cell
    const level2_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 50 } },
        .cols = &[_]Track{ .{ .fixed = 50 } },
    };

    const level2_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const level2_result = try level2_grid.layout(allocator, level1_cell, &level2_items);
    defer allocator.free(level2_result);

    const level2_cell = level2_result[0];
    try std.testing.expectEqual(50, level2_cell.width);
    try std.testing.expectEqual(50, level2_cell.height);

    // Level 3: Inner grid (1x1) inside Level 2's cell
    const level3_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 25 } },
        .cols = &[_]Track{ .{ .fixed = 25 } },
    };

    const level3_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const level3_result = try level3_grid.layout(allocator, level2_cell, &level3_items);
    defer allocator.free(level3_result);

    // Innermost cell should be correctly positioned and sized
    try std.testing.expectEqual(0, level3_result[0].x);
    try std.testing.expectEqual(0, level3_result[0].y);
    try std.testing.expectEqual(25, level3_result[0].width);
    try std.testing.expectEqual(25, level3_result[0].height);
}

test "nested grid - empty nested grid" {
    const allocator = std.testing.allocator;

    // Outer grid
    const outer_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 50 } },
        .cols = &[_]Track{ .{ .fixed = 50 } },
    };

    const outer_area = Rect{ .x = 0, .y = 0, .width = 50, .height = 50 };
    const outer_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const outer_result = try outer_grid.layout(allocator, outer_area, &outer_items);
    defer allocator.free(outer_result);

    const nested_cell = outer_result[0];

    // Layout empty inner grid in the cell
    const inner_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 25 } },
        .cols = &[_]Track{ .{ .fixed = 25 } },
    };

    const inner_items = [_]GridItem{};

    const inner_result = try inner_grid.layout(allocator, nested_cell, &inner_items);
    defer allocator.free(inner_result);

    // Empty inner grid should return empty result
    try std.testing.expectEqual(0, inner_result.len);
}

test "nested grid - oversized nested grid content" {
    const allocator = std.testing.allocator;

    // Outer grid with small cell
    const outer_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 50 } },
        .cols = &[_]Track{ .{ .fixed = 50 } },
    };

    const outer_area = Rect{ .x = 0, .y = 0, .width = 50, .height = 50 };
    const outer_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const outer_result = try outer_grid.layout(allocator, outer_area, &outer_items);
    defer allocator.free(outer_result);

    const nested_cell = outer_result[0];
    try std.testing.expectEqual(50, nested_cell.width);
    try std.testing.expectEqual(50, nested_cell.height);

    // Inner grid with large fixed tracks (100 each)
    // Should be clamped to available space (50x50)
    const inner_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 100 } },
        .cols = &[_]Track{ .{ .fixed = 100 } },
    };

    const inner_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const inner_result = try inner_grid.layout(allocator, nested_cell, &inner_items);
    defer allocator.free(inner_result);

    // Fixed track clamped to available space
    try std.testing.expectEqual(50, inner_result[0].width);
    try std.testing.expectEqual(50, inner_result[0].height);
}

test "nested grid - with gaps and span" {
    const allocator = std.testing.allocator;

    // Outer grid
    const outer_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 100 } },
        .cols = &[_]Track{ .{ .fixed = 100 } },
        .col_gap = 5,
        .row_gap = 5,
    };

    const outer_area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const outer_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const outer_result = try outer_grid.layout(allocator, outer_area, &outer_items);
    defer allocator.free(outer_result);

    const nested_cell = outer_result[0];

    // Inner grid with multiple columns, some spanned
    const inner_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 30 }, .{ .fixed = 30 } },
        .cols = &[_]Track{ .{ .fixed = 30 }, .{ .fixed = 30 } },
        .col_gap = 5,
        .row_gap = 5,
    };

    const inner_items = [_]GridItem{
        .{ .row = 1, .col = 1, .col_span = 2 }, // Spans 2 columns
        .{ .row = 2, .col = 1 },
        .{ .row = 2, .col = 2 },
    };

    const inner_result = try inner_grid.layout(allocator, nested_cell, &inner_items);
    defer allocator.free(inner_result);

    // First item spans 2 columns: 30 + 5 (gap) + 30 = 65
    try std.testing.expectEqual(65, inner_result[0].width);
}

test "nested grid - inner grid with fr units" {
    const allocator = std.testing.allocator;

    // Outer grid
    const outer_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 100 } },
        .cols = &[_]Track{ .{ .fixed = 100 } },
    };

    const outer_area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const outer_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const outer_result = try outer_grid.layout(allocator, outer_area, &outer_items);
    defer allocator.free(outer_result);

    const nested_cell = outer_result[0];
    try std.testing.expectEqual(100, nested_cell.width);

    // Inner grid with fr units should distribute the parent cell space
    const inner_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 50 } },
        .cols = &[_]Track{ .{ .fr = 1 }, .{ .fr = 2 }, .{ .fr = 1 } },
    };

    const inner_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
        .{ .row = 1, .col = 2 },
        .{ .row = 1, .col = 3 },
    };

    const inner_result = try inner_grid.layout(allocator, nested_cell, &inner_items);
    defer allocator.free(inner_result);

    // Total fr: 4, available: 100
    // Col 1: 1fr = 25, Col 2: 2fr = 50, Col 3: 1fr = 25
    try std.testing.expectEqual(25, inner_result[0].width);
    try std.testing.expectEqual(50, inner_result[1].width);
    try std.testing.expectEqual(25, inner_result[2].width);
}

test "nested grid - inner grid respects cell boundaries with padding" {
    const allocator = std.testing.allocator;

    // Outer grid
    const outer_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 100 } },
        .cols = &[_]Track{ .{ .fixed = 100 } },
    };

    const outer_area = Rect{ .x = 10, .y = 20, .width = 100, .height = 100 };
    const outer_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const outer_result = try outer_grid.layout(allocator, outer_area, &outer_items);
    defer allocator.free(outer_result);

    const nested_cell = outer_result[0];
    // Cell should be offset by outer area position
    try std.testing.expectEqual(10, nested_cell.x);
    try std.testing.expectEqual(20, nested_cell.y);
    try std.testing.expectEqual(100, nested_cell.width);
    try std.testing.expectEqual(100, nested_cell.height);

    // Inner grid should be positioned relative to the cell
    const inner_grid = Grid{
        .rows = &[_]Track{ .{ .fixed = 50 } },
        .cols = &[_]Track{ .{ .fixed = 50 } },
    };

    const inner_items = [_]GridItem{
        .{ .row = 1, .col = 1 },
    };

    const inner_result = try inner_grid.layout(allocator, nested_cell, &inner_items);
    defer allocator.free(inner_result);

    // Inner grid positions are relative to nested_cell, not the outer area
    try std.testing.expectEqual(10, inner_result[0].x);
    try std.testing.expectEqual(20, inner_result[0].y);
    try std.testing.expectEqual(50, inner_result[0].width);
    try std.testing.expectEqual(50, inner_result[0].height);
}
