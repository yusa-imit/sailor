//! Bounded Bresenham line iterator shared by every widget that draws a straight line.
//!
//! Yields the points of the segment (x0, y0) .. (x1, y1), both endpoints included, in order from
//! the start. A segment yields exactly `max(|dx|, |dy|) + 1` points, so every caller loop is
//! bounded by the geometry and by a counter rather than by hitting the endpoint exactly. The
//! last point is asserted to equal the endpoint. Coordinates may lie far off screen (any `i32`);
//! clipping is the caller's job. The iterator never allocates and holds no pointers.

const std = @import("std");
const assert = std.debug.assert;

/// One point on a rasterized line.
pub const Point = struct {
    x: i32,
    y: i32,
};

pub const LineIter = struct {
    x: i64,
    y: i64,
    x_end: i64,
    y_end: i64,
    dx: i64,
    dy: i64,
    step_x: i64,
    step_y: i64,
    err: i64,
    remaining_count: u64,

    /// Start a line from (x0, y0) to (x1, y1), both inclusive.
    pub fn init(x0: i32, y0: i32, x1: i32, y1: i32) LineIter {
        const dx: i64 = @intCast(@abs(@as(i64, x1) - @as(i64, x0)));
        const dy: i64 = @intCast(@abs(@as(i64, y1) - @as(i64, y0)));
        const iter: LineIter = .{
            .x = x0,
            .y = y0,
            .x_end = x1,
            .y_end = y1,
            .dx = dx,
            .dy = dy,
            .step_x = if (x1 > x0) 1 else -1,
            .step_y = if (y1 > y0) 1 else -1,
            .err = dx - dy,
            .remaining_count = @as(u64, @intCast(@max(dx, dy))) + 1,
        };
        assert(iter.remaining_count >= 1);
        assert(iter.remaining_count <= @as(u64, std.math.maxInt(u32)) + 1);
        return iter;
    }

    /// Number of points `next` will still yield.
    pub fn remaining(self: *const LineIter) u64 {
        return self.remaining_count;
    }

    /// The next point, or null once the endpoint has been yielded.
    pub fn next(self: *LineIter) ?Point {
        if (self.remaining_count == 0) return null;

        const point: Point = .{ .x = @intCast(self.x), .y = @intCast(self.y) };
        self.remaining_count -= 1;
        if (self.remaining_count == 0) {
            // The step count is derived from the geometry; reaching it must land on the endpoint.
            assert(self.x == self.x_end);
            assert(self.y == self.y_end);
            return point;
        }

        const err_twice = self.err * 2;
        if (err_twice > -self.dy) {
            self.err -= self.dy;
            self.x += self.step_x;
        }
        if (err_twice < self.dx) {
            self.err += self.dx;
            self.y += self.step_y;
        }
        return point;
    }
};

const expectEqual = std.testing.expectEqual;

fn collect(iter_start: LineIter, out: []Point) usize {
    var iter = iter_start;
    var count: usize = 0;
    while (iter.next()) |point| {
        out[count] = point;
        count += 1;
    }
    return count;
}

test "LineIter single point yields the point once" {
    var points: [4]Point = undefined;
    const count = collect(LineIter.init(5, 7, 5, 7), &points);
    try expectEqual(@as(usize, 1), count);
    try expectEqual(Point{ .x = 5, .y = 7 }, points[0]);
}

test "LineIter horizontal includes both endpoints" {
    var points: [8]Point = undefined;
    const count = collect(LineIter.init(2, 3, 5, 3), &points);
    try expectEqual(@as(usize, 4), count);
    for (points[0..count], 0..) |point, index| {
        try expectEqual(Point{ .x = 2 + @as(i32, @intCast(index)), .y = 3 }, point);
    }
}

test "LineIter vertical reversed walks downward in x and y order" {
    var points: [8]Point = undefined;
    const count = collect(LineIter.init(4, 6, 4, 2), &points);
    try expectEqual(@as(usize, 5), count);
    try expectEqual(Point{ .x = 4, .y = 6 }, points[0]);
    try expectEqual(Point{ .x = 4, .y = 5 }, points[1]);
    try expectEqual(Point{ .x = 4, .y = 2 }, points[4]);
}

test "LineIter 45 degrees steps both axes each point" {
    var points: [8]Point = undefined;
    const count = collect(LineIter.init(0, 0, 3, 3), &points);
    try expectEqual(@as(usize, 4), count);
    for (points[0..count], 0..) |point, index| {
        const value: i32 = @intCast(index);
        try expectEqual(Point{ .x = value, .y = value }, point);
    }
}

test "LineIter steep line yields one point per row" {
    var points: [16]Point = undefined;
    const count = collect(LineIter.init(0, 0, 2, 6), &points);
    try expectEqual(@as(usize, 7), count);
    for (points[0..count], 0..) |point, index| {
        try expectEqual(@as(i32, @intCast(index)), point.y);
        try std.testing.expect(point.x >= 0 and point.x <= 2);
    }
    try expectEqual(Point{ .x = 2, .y = 6 }, points[6]);
}

test "LineIter shallow line matches Bresenham reference points" {
    var points: [8]Point = undefined;
    const count = collect(LineIter.init(0, 0, 5, 2), &points);
    const expected = [_]Point{
        .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 1 },
        .{ .x = 3, .y = 1 }, .{ .x = 4, .y = 2 }, .{ .x = 5, .y = 2 },
    };
    try expectEqual(expected.len, count);
    for (expected, points[0..count]) |want, got| try expectEqual(want, got);
}

test "LineIter reversed line visits the same points as the forward line" {
    var forward: [16]Point = undefined;
    var backward: [16]Point = undefined;
    const forward_count = collect(LineIter.init(1, 1, 8, 4), &forward);
    const backward_count = collect(LineIter.init(8, 4, 1, 1), &backward);
    try expectEqual(forward_count, backward_count);
    try expectEqual(forward[0], backward[backward_count - 1]);
    try expectEqual(forward[forward_count - 1], backward[0]);
}

test "LineIter negative coordinates reach the endpoint" {
    var points: [16]Point = undefined;
    const count = collect(LineIter.init(-3, -2, 2, 1), &points);
    try expectEqual(@as(usize, 6), count);
    try expectEqual(Point{ .x = -3, .y = -2 }, points[0]);
    try expectEqual(Point{ .x = 2, .y = 1 }, points[count - 1]);
}

test "LineIter far off-screen endpoint has a bounded length" {
    const iter = LineIter.init(0, 0, 1_000_000, -3);
    try expectEqual(@as(u64, 1_000_001), iter.remaining());

    var iter_walk = iter;
    var count: u64 = 0;
    var last: Point = .{ .x = 0, .y = 0 };
    while (iter_walk.next()) |point| {
        count += 1;
        last = point;
    }
    try expectEqual(@as(u64, 1_000_001), count);
    try expectEqual(Point{ .x = 1_000_000, .y = -3 }, last);
    try expectEqual(@as(u64, 0), iter_walk.remaining());
}

test "LineIter extreme i32 span does not overflow" {
    var iter = LineIter.init(std.math.minInt(i32), 0, std.math.maxInt(i32), 0);
    try expectEqual(@as(u64, 1) << 32, iter.remaining());
    const first = iter.next().?;
    try expectEqual(Point{ .x = std.math.minInt(i32), .y = 0 }, first);
    try expectEqual((@as(u64, 1) << 32) - 1, iter.remaining());
}

test "LineIter returns null after the endpoint" {
    var iter = LineIter.init(0, 0, 1, 0);
    try std.testing.expect(iter.next() != null);
    try std.testing.expect(iter.next() != null);
    try expectEqual(@as(?Point, null), iter.next());
    try expectEqual(@as(?Point, null), iter.next());
}
