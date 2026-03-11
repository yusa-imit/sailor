const std = @import("std");

/// Touch point with position and unique identifier
pub const TouchPoint = struct {
    id: u32,
    x: u16,
    y: u16,
    pressure: f32 = 1.0, // 0.0-1.0 normalized pressure (future use)

    pub fn init(id: u32, x: u16, y: u16) TouchPoint {
        return .{ .id = id, .x = x, .y = y };
    }
};

/// Touch gesture types
pub const GestureType = enum {
    tap,
    double_tap,
    long_press,
    swipe_left,
    swipe_right,
    swipe_up,
    swipe_down,
    pinch_in,
    pinch_out,
};

/// Direction for swipe gestures
pub const SwipeDirection = enum {
    left,
    right,
    up,
    down,

    pub fn fromDelta(dx: i32, dy: i32) ?SwipeDirection {
        const abs_dx = if (dx < 0) -dx else dx;
        const abs_dy = if (dy < 0) -dy else dy;

        // Primary direction based on larger delta
        if (abs_dx > abs_dy) {
            return if (dx > 0) .right else .left;
        } else if (abs_dy > abs_dx) {
            return if (dy > 0) .down else .up;
        }
        return null; // No clear direction
    }
};

/// Pinch gesture data
pub const PinchData = struct {
    scale: f32, // Relative scale factor (1.0 = no change, >1.0 = zoom out, <1.0 = zoom in)
    center_x: u16,
    center_y: u16,
};

/// Touch gesture event
pub const TouchGesture = union(GestureType) {
    tap: TouchPoint,
    double_tap: TouchPoint,
    long_press: TouchPoint,
    swipe_left: struct { start: TouchPoint, end: TouchPoint },
    swipe_right: struct { start: TouchPoint, end: TouchPoint },
    swipe_up: struct { start: TouchPoint, end: TouchPoint },
    swipe_down: struct { start: TouchPoint, end: TouchPoint },
    pinch_in: PinchData,
    pinch_out: PinchData,

    pub fn getType(self: TouchGesture) GestureType {
        return @as(GestureType, self);
    }
};

const MAX_TOUCHES = 10;

/// Touch state tracker for gesture recognition
pub const TouchTracker = struct {
    const Self = @This();

    // Active touch points (max 10 simultaneous touches)
    active_touches: [MAX_TOUCHES]TouchPoint = undefined,
    active_count: usize = 0,

    // Gesture detection state
    tap_start_time: i64 = 0,
    tap_point: ?TouchPoint = null,
    last_tap_time: i64 = 0,
    last_tap_point: ?TouchPoint = null,
    long_press_triggered: bool = false,

    // Two-finger tracking for pinch
    initial_distance: ?f32 = null,

    // Thresholds (in cells/milliseconds)
    tap_time_threshold_ms: i64 = 300,
    double_tap_time_threshold_ms: i64 = 500,
    long_press_time_threshold_ms: i64 = 800,
    swipe_distance_threshold: u16 = 3, // Minimum cells to detect swipe
    tap_move_tolerance: u16 = 1, // Max movement to still count as tap

    pub fn init() Self {
        return .{};
    }

    fn getSlice(self: *Self) []TouchPoint {
        return self.active_touches[0..self.active_count];
    }

    fn getSliceConst(self: *const Self) []const TouchPoint {
        return self.active_touches[0..self.active_count];
    }

    /// Add or update a touch point
    pub fn touchDown(self: *Self, point: TouchPoint, timestamp_ms: i64) void {
        // Check if this touch ID already exists (update)
        for (self.getSlice()) |*touch| {
            if (touch.id == point.id) {
                touch.* = point;
                return;
            }
        }

        // Add new touch
        if (self.active_count < MAX_TOUCHES) {
            self.active_touches[self.active_count] = point;
            self.active_count += 1;
        }

        // If first touch, start tap tracking
        if (self.active_count == 1) {
            self.tap_start_time = timestamp_ms;
            self.tap_point = point;
            self.long_press_triggered = false;
        }

        // If two touches, start pinch tracking
        if (self.active_count == 2) {
            const t0 = self.active_touches[0];
            const t1 = self.active_touches[1];
            self.initial_distance = distance(t0, t1);
        }
    }

    /// Update existing touch point
    pub fn touchMove(self: *Self, point: TouchPoint) void {
        for (self.getSlice()) |*touch| {
            if (touch.id == point.id) {
                touch.* = point;
                return;
            }
        }
    }

    /// Remove a touch point and detect gestures
    pub fn touchUp(self: *Self, point: TouchPoint, timestamp_ms: i64) ?TouchGesture {
        // Remove the touch from active list
        var found_index: ?usize = null;
        for (self.getSlice(), 0..) |touch, i| {
            if (touch.id == point.id) {
                found_index = i;
                break;
            }
        }

        if (found_index) |idx| {
            // Swap remove
            if (idx < self.active_count - 1) {
                self.active_touches[idx] = self.active_touches[self.active_count - 1];
            }
            self.active_count -= 1;
        }

        // Detect gesture if this was the last touch
        if (self.active_count == 0) {
            return self.detectGesture(point, timestamp_ms);
        }

        // Reset pinch tracking if we had 2 touches
        if (self.active_count < 2) {
            self.initial_distance = null;
        }

        return null;
    }

    /// Get current pinch gesture if in progress
    pub fn getPinchGesture(self: *Self) ?TouchGesture {
        if (self.active_count != 2) return null;
        if (self.initial_distance == null) return null;

        const t0 = self.active_touches[0];
        const t1 = self.active_touches[1];
        const current_dist = distance(t0, t1);
        const initial_dist = self.initial_distance.?;

        const scale = current_dist / initial_dist;

        const center_x = @as(u16, @intCast((@as(u32, t0.x) + @as(u32, t1.x)) / 2));
        const center_y = @as(u16, @intCast((@as(u32, t0.y) + @as(u32, t1.y)) / 2));

        const pinch_data = PinchData{
            .scale = scale,
            .center_x = center_x,
            .center_y = center_y,
        };

        // Threshold to avoid jitter (5% change minimum)
        if (scale < 0.95) {
            return TouchGesture{ .pinch_in = pinch_data };
        } else if (scale > 1.05) {
            return TouchGesture{ .pinch_out = pinch_data };
        }

        return null;
    }

    /// Check for long press (call periodically)
    pub fn checkLongPress(self: *Self, timestamp_ms: i64) ?TouchGesture {
        if (self.active_count != 1) return null;
        if (self.long_press_triggered) return null;
        if (self.tap_point == null) return null;

        const duration = timestamp_ms - self.tap_start_time;
        if (duration >= self.long_press_time_threshold_ms) {
            self.long_press_triggered = true;
            return TouchGesture{ .long_press = self.tap_point.? };
        }

        return null;
    }

    fn detectGesture(self: *Self, end_point: TouchPoint, timestamp_ms: i64) ?TouchGesture {
        const start_point = self.tap_point orelse return null;
        const duration = timestamp_ms - self.tap_start_time;

        const dx = @as(i32, end_point.x) - @as(i32, start_point.x);
        const dy = @as(i32, end_point.y) - @as(i32, start_point.y);
        const abs_dx: u16 = @intCast(if (dx < 0) -dx else dx);
        const abs_dy: u16 = @intCast(if (dy < 0) -dy else dy);
        const move_distance = @max(abs_dx, abs_dy);

        // Swipe detection (fast movement with distance)
        if (move_distance >= self.swipe_distance_threshold and duration < self.tap_time_threshold_ms) {
            const direction = SwipeDirection.fromDelta(dx, dy) orelse return null;

            return switch (direction) {
                .left => TouchGesture{ .swipe_left = .{ .start = start_point, .end = end_point } },
                .right => TouchGesture{ .swipe_right = .{ .start = start_point, .end = end_point } },
                .up => TouchGesture{ .swipe_up = .{ .start = start_point, .end = end_point } },
                .down => TouchGesture{ .swipe_down = .{ .start = start_point, .end = end_point } },
            };
        }

        // Long press already handled by checkLongPress()
        if (self.long_press_triggered) {
            return null; // Already emitted
        }

        // Tap detection (short duration, minimal movement)
        if (duration < self.tap_time_threshold_ms and move_distance <= self.tap_move_tolerance) {
            // Check for double tap
            const time_since_last_tap = timestamp_ms - self.last_tap_time;
            if (time_since_last_tap < self.double_tap_time_threshold_ms) {
                if (self.last_tap_point) |last_pt| {
                    const last_dx = @as(i32, end_point.x) - @as(i32, last_pt.x);
                    const last_dy = @as(i32, end_point.y) - @as(i32, last_pt.y);
                    const last_abs_dx: u16 = @intCast(if (last_dx < 0) -last_dx else last_dx);
                    const last_abs_dy: u16 = @intCast(if (last_dy < 0) -last_dy else last_dy);
                    const last_move = @max(last_abs_dx, last_abs_dy);

                    if (last_move <= self.tap_move_tolerance) {
                        // Reset double tap tracking
                        self.last_tap_time = 0;
                        self.last_tap_point = null;
                        return TouchGesture{ .double_tap = end_point };
                    }
                }
            }

            // Single tap
            self.last_tap_time = timestamp_ms;
            self.last_tap_point = end_point;
            return TouchGesture{ .tap = end_point };
        }

        return null;
    }

    fn distance(p1: TouchPoint, p2: TouchPoint) f32 {
        const dx = @as(f32, @floatFromInt(@as(i32, p1.x) - @as(i32, p2.x)));
        const dy = @as(f32, @floatFromInt(@as(i32, p1.y) - @as(i32, p2.y)));
        return @sqrt(dx * dx + dy * dy);
    }
};

// ============================================================
// TESTS
// ============================================================

const testing = std.testing;

test "TouchPoint creation" {
    const point = TouchPoint.init(1, 10, 20);
    try testing.expectEqual(@as(u32, 1), point.id);
    try testing.expectEqual(@as(u16, 10), point.x);
    try testing.expectEqual(@as(u16, 20), point.y);
    try testing.expectEqual(@as(f32, 1.0), point.pressure);
}

test "SwipeDirection.fromDelta - horizontal" {
    const left = SwipeDirection.fromDelta(-10, 2);
    try testing.expectEqual(SwipeDirection.left, left.?);

    const right = SwipeDirection.fromDelta(10, -2);
    try testing.expectEqual(SwipeDirection.right, right.?);
}

test "SwipeDirection.fromDelta - vertical" {
    const up = SwipeDirection.fromDelta(2, -10);
    try testing.expectEqual(SwipeDirection.up, up.?);

    const down = SwipeDirection.fromDelta(-2, 10);
    try testing.expectEqual(SwipeDirection.down, down.?);
}

test "SwipeDirection.fromDelta - no clear direction" {
    const none = SwipeDirection.fromDelta(0, 0);
    try testing.expectEqual(@as(?SwipeDirection, null), none);
}

test "TouchTracker init" {
    const tracker = TouchTracker.init();
    try testing.expectEqual(@as(usize, 0), tracker.active_count);
    try testing.expectEqual(@as(i64, 0), tracker.tap_start_time);
    try testing.expectEqual(@as(?TouchPoint, null), tracker.tap_point);
}

test "TouchTracker - single tap" {
    var tracker = TouchTracker.init();
    const point = TouchPoint.init(1, 10, 20);

    tracker.touchDown(point, 1000);
    try testing.expectEqual(@as(usize, 1), tracker.active_count);

    const gesture = tracker.touchUp(point, 1100); // 100ms duration
    try testing.expect(gesture != null);
    try testing.expectEqual(GestureType.tap, gesture.?.getType());
}

test "TouchTracker - double tap" {
    var tracker = TouchTracker.init();
    const point = TouchPoint.init(1, 10, 20);

    // First tap
    tracker.touchDown(point, 1000);
    const g1 = tracker.touchUp(point, 1100);
    try testing.expectEqual(GestureType.tap, g1.?.getType());

    // Second tap within threshold (500ms)
    tracker.touchDown(point, 1300);
    const g2 = tracker.touchUp(point, 1400);
    try testing.expectEqual(GestureType.double_tap, g2.?.getType());
}

test "TouchTracker - long press" {
    var tracker = TouchTracker.init();
    const point = TouchPoint.init(1, 10, 20);

    tracker.touchDown(point, 1000);

    // Check before threshold
    const g1 = tracker.checkLongPress(1700); // 700ms
    try testing.expectEqual(@as(?TouchGesture, null), g1);

    // Check after threshold
    const g2 = tracker.checkLongPress(1900); // 900ms
    try testing.expect(g2 != null);
    try testing.expectEqual(GestureType.long_press, g2.?.getType());

    // Should not trigger again
    const g3 = tracker.checkLongPress(2000);
    try testing.expectEqual(@as(?TouchGesture, null), g3);
}

test "TouchTracker - swipe left" {
    var tracker = TouchTracker.init();
    tracker.swipe_distance_threshold = 5; // Minimum 5 cells

    const start = TouchPoint.init(1, 20, 10);
    const end = TouchPoint.init(1, 10, 10); // Moved 10 cells left

    tracker.touchDown(start, 1000);
    const gesture = tracker.touchUp(end, 1100); // 100ms (fast)

    try testing.expect(gesture != null);
    try testing.expectEqual(GestureType.swipe_left, gesture.?.getType());
}

test "TouchTracker - swipe right" {
    var tracker = TouchTracker.init();
    tracker.swipe_distance_threshold = 5;

    const start = TouchPoint.init(1, 10, 10);
    const end = TouchPoint.init(1, 20, 10); // Moved 10 cells right

    tracker.touchDown(start, 1000);
    const gesture = tracker.touchUp(end, 1100);

    try testing.expect(gesture != null);
    try testing.expectEqual(GestureType.swipe_right, gesture.?.getType());
}

test "TouchTracker - swipe up" {
    var tracker = TouchTracker.init();
    tracker.swipe_distance_threshold = 5;

    const start = TouchPoint.init(1, 10, 20);
    const end = TouchPoint.init(1, 10, 10); // Moved 10 cells up

    tracker.touchDown(start, 1000);
    const gesture = tracker.touchUp(end, 1100);

    try testing.expect(gesture != null);
    try testing.expectEqual(GestureType.swipe_up, gesture.?.getType());
}

test "TouchTracker - swipe down" {
    var tracker = TouchTracker.init();
    tracker.swipe_distance_threshold = 5;

    const start = TouchPoint.init(1, 10, 10);
    const end = TouchPoint.init(1, 10, 20); // Moved 10 cells down

    tracker.touchDown(start, 1000);
    const gesture = tracker.touchUp(end, 1100);

    try testing.expect(gesture != null);
    try testing.expectEqual(GestureType.swipe_down, gesture.?.getType());
}

test "TouchTracker - pinch in" {
    var tracker = TouchTracker.init();

    const t1_start = TouchPoint.init(1, 10, 10);
    const t2_start = TouchPoint.init(2, 30, 10); // 20 cells apart

    tracker.touchDown(t1_start, 1000);
    tracker.touchDown(t2_start, 1000);

    // Move fingers closer (pinch in)
    const t1_end = TouchPoint.init(1, 15, 10);
    const t2_end = TouchPoint.init(2, 25, 10); // Now 10 cells apart

    tracker.touchMove(t1_end);
    tracker.touchMove(t2_end);

    const gesture = tracker.getPinchGesture();
    try testing.expect(gesture != null);
    try testing.expectEqual(GestureType.pinch_in, gesture.?.getType());
}

test "TouchTracker - pinch out" {
    var tracker = TouchTracker.init();

    const t1_start = TouchPoint.init(1, 15, 10);
    const t2_start = TouchPoint.init(2, 25, 10); // 10 cells apart

    tracker.touchDown(t1_start, 1000);
    tracker.touchDown(t2_start, 1000);

    // Move fingers apart (pinch out)
    const t1_end = TouchPoint.init(1, 10, 10);
    const t2_end = TouchPoint.init(2, 30, 10); // Now 20 cells apart

    tracker.touchMove(t1_end);
    tracker.touchMove(t2_end);

    const gesture = tracker.getPinchGesture();
    try testing.expect(gesture != null);
    try testing.expectEqual(GestureType.pinch_out, gesture.?.getType());
}

test "TouchTracker - tap with small movement tolerance" {
    var tracker = TouchTracker.init();
    tracker.tap_move_tolerance = 2; // Allow 2 cells of movement

    const start = TouchPoint.init(1, 10, 10);
    const end = TouchPoint.init(1, 11, 11); // Moved 1 cell diagonally

    tracker.touchDown(start, 1000);
    const gesture = tracker.touchUp(end, 1100);

    try testing.expect(gesture != null);
    try testing.expectEqual(GestureType.tap, gesture.?.getType());
}

test "TouchTracker - swipe requires minimum distance" {
    var tracker = TouchTracker.init();
    tracker.swipe_distance_threshold = 10;

    const start = TouchPoint.init(1, 10, 10);
    const end = TouchPoint.init(1, 15, 10); // Only 5 cells (below threshold)

    tracker.touchDown(start, 1000);
    const gesture = tracker.touchUp(end, 1100);

    // Should not detect as swipe (distance too small), likely no gesture
    try testing.expect(gesture == null or gesture.?.getType() != .swipe_right);
}

test "TouchTracker - multiple touches" {
    var tracker = TouchTracker.init();

    const t1 = TouchPoint.init(1, 10, 10);
    const t2 = TouchPoint.init(2, 20, 20);
    const t3 = TouchPoint.init(3, 30, 30);

    tracker.touchDown(t1, 1000);
    try testing.expectEqual(@as(usize, 1), tracker.active_count);

    tracker.touchDown(t2, 1000);
    try testing.expectEqual(@as(usize, 2), tracker.active_count);

    tracker.touchDown(t3, 1000);
    try testing.expectEqual(@as(usize, 3), tracker.active_count);

    // Remove middle touch
    _ = tracker.touchUp(t2, 1100);
    try testing.expectEqual(@as(usize, 2), tracker.active_count);
}

test "TouchGesture.getType" {
    const tap = TouchGesture{ .tap = TouchPoint.init(1, 10, 10) };
    try testing.expectEqual(GestureType.tap, tap.getType());

    const swipe = TouchGesture{
        .swipe_left = .{
            .start = TouchPoint.init(1, 20, 10),
            .end = TouchPoint.init(1, 10, 10),
        },
    };
    try testing.expectEqual(GestureType.swipe_left, swipe.getType());

    const pinch = TouchGesture{
        .pinch_in = .{ .scale = 0.5, .center_x = 10, .center_y = 10 },
    };
    try testing.expectEqual(GestureType.pinch_in, pinch.getType());
}
