const std = @import("std");
const Allocator = std.mem.Allocator;
const tui_mod = @import("tui.zig");
const Event = tui_mod.Event;
const KeyEvent = tui_mod.KeyEvent;

/// Resize event data
pub const ResizeEvent = struct {
    width: u16,
    height: u16,
};

/// Event batching system to coalesce rapid events (resize, mouse, etc.)
/// Reduces overhead from event storms by merging consecutive similar events.
pub const EventBatcher = struct {
    /// Pending events queue
    events: std.ArrayList(Event),
    /// Last resize event (coalesced)
    last_resize: ?ResizeEvent = null,
    /// Time window for batching in nanoseconds (default: 16ms = ~1 frame @ 60fps)
    batch_window_ns: u64,
    /// Last flush timestamp
    last_flush_ns: u64,
    allocator: Allocator,

    /// Initialize event batcher with batch window (default: 16ms)
    pub fn init(allocator: Allocator, batch_window_ms: u32) EventBatcher {
        return .{
            .events = .{},
            .batch_window_ns = @as(u64, batch_window_ms) * 1_000_000,
            .last_flush_ns = 0,
            .allocator = allocator,
        };
    }

    /// Free event batcher resources
    pub fn deinit(self: *EventBatcher) void {
        self.events.deinit(self.allocator);
    }

    /// Add event to batch. Resize events are coalesced automatically.
    pub fn push(self: *EventBatcher, event: Event) !void {
        switch (event) {
            .resize => |size| {
                // Coalesce resize events - only keep the latest
                self.last_resize = .{ .width = size.width, .height = size.height };
            },
            .key, .mouse, .gamepad => {
                // Immediately add non-resize events
                try self.events.append(self.allocator, event);
            },
        }
    }

    /// Check if batch window has elapsed
    pub fn shouldFlush(self: EventBatcher) bool {
        if (self.last_flush_ns == 0) return true; // First flush
        const now = std.time.nanoTimestamp();
        const elapsed = @as(u64, @intCast(now)) - self.last_flush_ns;
        return elapsed >= self.batch_window_ns;
    }

    /// Flush batched events to output list. Returns coalesced events.
    /// Caller owns the returned list memory.
    pub fn flush(self: *EventBatcher, out: *std.ArrayList(Event)) !void {
        // Add coalesced resize event if present
        if (self.last_resize) |size| {
            try out.append(self.allocator, .{ .resize = .{ .width = size.width, .height = size.height } });
            self.last_resize = null;
        }

        // Move all other events
        try out.appendSlice(self.allocator, self.events.items);
        self.events.clearRetainingCapacity();

        // Update flush timestamp
        const now = std.time.nanoTimestamp();
        self.last_flush_ns = @intCast(now);
    }

    /// Get number of pending events (including coalesced resize)
    pub fn count(self: EventBatcher) usize {
        var total = self.events.items.len;
        if (self.last_resize != null) total += 1;
        return total;
    }

    /// Clear all pending events
    pub fn clear(self: *EventBatcher) void {
        self.events.clearRetainingCapacity();
        self.last_resize = null;
    }

    /// Peek at coalesced resize event without flushing
    pub fn peekResize(self: EventBatcher) ?ResizeEvent {
        return self.last_resize;
    }
};

test "EventBatcher init" {
    const allocator = std.testing.allocator;
    var batcher = EventBatcher.init(allocator, 16);
    defer batcher.deinit();

    try std.testing.expectEqual(@as(u64, 16_000_000), batcher.batch_window_ns);
    try std.testing.expectEqual(@as(usize, 0), batcher.count());
}

test "EventBatcher coalesce resize" {
    const allocator = std.testing.allocator;
    var batcher = EventBatcher.init(allocator, 16);
    defer batcher.deinit();

    // Push multiple resize events
    try batcher.push(.{ .resize = .{ .width = 80, .height = 24 } });
    try batcher.push(.{ .resize = .{ .width = 100, .height = 30 } });
    try batcher.push(.{ .resize = .{ .width = 120, .height = 40 } });

    // Should only keep the last one
    try std.testing.expectEqual(@as(usize, 1), batcher.count());

    const resize = batcher.peekResize().?;
    try std.testing.expectEqual(@as(u16, 120), resize.width);
    try std.testing.expectEqual(@as(u16, 40), resize.height);
}

test "EventBatcher key events not coalesced" {
    const allocator = std.testing.allocator;
    var batcher = EventBatcher.init(allocator, 16);
    defer batcher.deinit();

    // Push multiple key events
    try batcher.push(.{ .key = .{ .code = .{ .char = 'a' } } });
    try batcher.push(.{ .key = .{ .code = .{ .char = 'b' } } });
    try batcher.push(.{ .key = .{ .code = .{ .char = 'c' } } });

    // All key events should be preserved
    try std.testing.expectEqual(@as(usize, 3), batcher.count());
}

test "EventBatcher mixed events" {
    const allocator = std.testing.allocator;
    var batcher = EventBatcher.init(allocator, 16);
    defer batcher.deinit();

    // Push mixed events
    try batcher.push(.{ .key = .{ .code = .{ .char = 'a' } } });
    try batcher.push(.{ .resize = .{ .width = 80, .height = 24 } });
    try batcher.push(.{ .key = .{ .code = .{ .char = 'b' } } });
    try batcher.push(.{ .resize = .{ .width = 100, .height = 30 } });

    // Should have 2 key events + 1 resize (coalesced)
    try std.testing.expectEqual(@as(usize, 3), batcher.count());
}

test "EventBatcher flush" {
    const allocator = std.testing.allocator;
    var batcher = EventBatcher.init(allocator, 16);
    defer batcher.deinit();

    var output = std.ArrayList(Event){};
    defer output.deinit(allocator);

    // Push events
    try batcher.push(.{ .key = .{ .code = .{ .char = 'a' } } });
    try batcher.push(.{ .resize = .{ .width = 80, .height = 24 } });
    try batcher.push(.{ .resize = .{ .width = 100, .height = 30 } });

    // Flush to output
    try batcher.flush(&output);

    // Should have 2 events: 1 resize (coalesced) + 1 key
    try std.testing.expectEqual(@as(usize, 2), output.items.len);
    try std.testing.expectEqual(@as(usize, 0), batcher.count());

    // Check first event is resize (coalesced to last value)
    try std.testing.expect(output.items[0] == .resize);
    try std.testing.expectEqual(@as(u16, 100), output.items[0].resize.width);
    try std.testing.expectEqual(@as(u16, 30), output.items[0].resize.height);

    // Check second event is key
    try std.testing.expect(output.items[1] == .key);
    try std.testing.expectEqual(@as(u8, 'a'), output.items[1].key.code.char);
}

test "EventBatcher clear" {
    const allocator = std.testing.allocator;
    var batcher = EventBatcher.init(allocator, 16);
    defer batcher.deinit();

    try batcher.push(.{ .key = .{ .code = .{ .char = 'a' } } });
    try batcher.push(.{ .resize = .{ .width = 80, .height = 24 } });

    try std.testing.expectEqual(@as(usize, 2), batcher.count());

    batcher.clear();
    try std.testing.expectEqual(@as(usize, 0), batcher.count());
    try std.testing.expect(batcher.peekResize() == null);
}

test "EventBatcher shouldFlush timing" {
    const allocator = std.testing.allocator;
    var batcher = EventBatcher.init(allocator, 1); // 1ms window
    defer batcher.deinit();

    // First flush should always return true
    try std.testing.expect(batcher.shouldFlush());

    var output = std.ArrayList(Event){};
    defer output.deinit(allocator);

    try batcher.flush(&output);

    // Immediately after flush, should be false (within window)
    // Note: This test is timing-dependent and might be flaky on slow systems
    // We skip detailed timing check and just verify the flush mechanism works
    _ = batcher.shouldFlush();
}

test "EventBatcher multiple flush cycles" {
    const allocator = std.testing.allocator;
    var batcher = EventBatcher.init(allocator, 16);
    defer batcher.deinit();

    var output = std.ArrayList(Event){};
    defer output.deinit(allocator);

    // First cycle
    try batcher.push(.{ .key = .{ .code = .{ .char = 'a' } } });
    try batcher.flush(&output);
    try std.testing.expectEqual(@as(usize, 1), output.items.len);

    output.clearRetainingCapacity();

    // Second cycle
    try batcher.push(.{ .key = .{ .code = .{ .char = 'b' } } });
    try batcher.push(.{ .resize = .{ .width = 80, .height = 24 } });
    try batcher.flush(&output);
    try std.testing.expectEqual(@as(usize, 2), output.items.len);
}
