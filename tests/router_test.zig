//! ScreenRouter Tests — v2.20.0
//!
//! Tests for the ScreenRouter: push/pop navigation, lifecycle callbacks,
//! replace, reset, dispatch routing, and depth tracking.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const ScreenHandle = sailor.ScreenHandle;
const ScreenResult = sailor.ScreenResult;
const ScreenRouter = sailor.ScreenRouter;
const Buffer = sailor.Buffer;
const Rect = sailor.Rect;
const Event = sailor.tui.Event;
const Allocator = std.mem.Allocator;

// Minimal no-op screen for basic navigation tests
const NopScreen = struct {
    pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
    pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
    pub fn onEnter(_: *@This()) void {}
    pub fn onLeave(_: *@This()) void {}
};

// Screen that logs Enter/Leave events as byte pairs: 'E'/<id>, 'L'/<id>
// Stores allocator so it can append to the ArrayList in Zig 0.15 (unmanaged API).
const LogScreen = struct {
    id: u8,
    log_ptr: *std.ArrayList(u8),
    alloc: Allocator,

    pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
    pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
    pub fn onEnter(self: *@This()) void {
        self.log_ptr.append(self.alloc, 'E') catch {};
        self.log_ptr.append(self.alloc, self.id) catch {};
    }
    pub fn onLeave(self: *@This()) void {
        self.log_ptr.append(self.alloc, 'L') catch {};
        self.log_ptr.append(self.alloc, self.id) catch {};
    }
};

// ============================================================================
// Initial state
// ============================================================================

test "ScreenRouter starts empty and not running" {
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try testing.expect(!r.isRunning());
    try testing.expectEqual(@as(usize, 0), r.depth());
}

// ============================================================================
// reset()
// ============================================================================

test "ScreenRouter.reset makes router running with depth 1" {
    var s = NopScreen{};
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(NopScreen, &s));
    try testing.expect(r.isRunning());
    try testing.expectEqual(@as(usize, 1), r.depth());
}

test "ScreenRouter.reset calls onEnter on new screen" {
    var entered: u32 = 0;
    const EnterTrack = struct {
        entered_ptr: *u32,
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(self: *@This()) void { self.entered_ptr.* += 1; }
        pub fn onLeave(_: *@This()) void {}
    };
    var s = EnterTrack{ .entered_ptr = &entered };
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(EnterTrack, &s));
    try testing.expectEqual(@as(u32, 1), entered);
}

test "ScreenRouter.reset clears previous stack and calls onLeave on all" {
    var log: std.ArrayList(u8) = .empty;
    defer log.deinit(testing.allocator);

    var s1 = LogScreen{ .id = '1', .log_ptr = &log, .alloc = testing.allocator };
    var s2 = LogScreen{ .id = '2', .log_ptr = &log, .alloc = testing.allocator };
    var s3 = LogScreen{ .id = '3', .log_ptr = &log, .alloc = testing.allocator };

    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();

    try r.reset(ScreenHandle.init(LogScreen, &s1));
    try r.push(ScreenHandle.init(LogScreen, &s2));
    // log: E1 L1 E2

    log.clearRetainingCapacity();

    try r.reset(ScreenHandle.init(LogScreen, &s3));
    // reset should: L2, L1 (top-to-bottom), then E3
    // Expected: L2 L1 E3
    try testing.expectEqualSlices(u8, "L2L1E3", log.items);
    try testing.expectEqual(@as(usize, 1), r.depth());
}

// ============================================================================
// push()
// ============================================================================

test "ScreenRouter.push increases depth" {
    var s1 = NopScreen{};
    var s2 = NopScreen{};
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(NopScreen, &s1));
    try r.push(ScreenHandle.init(NopScreen, &s2));
    try testing.expectEqual(@as(usize, 2), r.depth());
}

test "ScreenRouter.push suspends current screen (onLeave) and enters new (onEnter)" {
    var log: std.ArrayList(u8) = .empty;
    defer log.deinit(testing.allocator);

    var s1 = LogScreen{ .id = '1', .log_ptr = &log, .alloc = testing.allocator };
    var s2 = LogScreen{ .id = '2', .log_ptr = &log, .alloc = testing.allocator };

    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();

    try r.reset(ScreenHandle.init(LogScreen, &s1));
    try r.push(ScreenHandle.init(LogScreen, &s2));

    // E1 (from reset), L1 (suspend s1), E2 (enter s2)
    try testing.expectEqualSlices(u8, "E1L1E2", log.items);
}

test "ScreenRouter.push multiple times increases depth" {
    var s1 = NopScreen{};
    var s2 = NopScreen{};
    var s3 = NopScreen{};
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(NopScreen, &s1));
    try r.push(ScreenHandle.init(NopScreen, &s2));
    try r.push(ScreenHandle.init(NopScreen, &s3));
    try testing.expectEqual(@as(usize, 3), r.depth());
}

// ============================================================================
// pop()
// ============================================================================

test "ScreenRouter.pop on empty stack is a no-op" {
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    r.pop(); // should not crash
    try testing.expect(!r.isRunning());
}

test "ScreenRouter.pop decreases depth" {
    var s1 = NopScreen{};
    var s2 = NopScreen{};
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(NopScreen, &s1));
    try r.push(ScreenHandle.init(NopScreen, &s2));
    r.pop();
    try testing.expectEqual(@as(usize, 1), r.depth());
}

test "ScreenRouter.pop calls onLeave on top, onEnter on resumed" {
    var log: std.ArrayList(u8) = .empty;
    defer log.deinit(testing.allocator);

    var s1 = LogScreen{ .id = '1', .log_ptr = &log, .alloc = testing.allocator };
    var s2 = LogScreen{ .id = '2', .log_ptr = &log, .alloc = testing.allocator };

    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();

    try r.reset(ScreenHandle.init(LogScreen, &s1));
    try r.push(ScreenHandle.init(LogScreen, &s2));
    log.clearRetainingCapacity();

    r.pop();
    // L2 (leave s2), E1 (resume s1)
    try testing.expectEqualSlices(u8, "L2E1", log.items);
}

test "ScreenRouter.pop all screens makes router not running" {
    var s = NopScreen{};
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(NopScreen, &s));
    r.pop();
    try testing.expect(!r.isRunning());
    try testing.expectEqual(@as(usize, 0), r.depth());
}

test "ScreenRouter.pop when depth 1 does not call onEnter on anything" {
    var entered: u32 = 0;
    const EnterTrack = struct {
        entered_ptr: *u32,
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(self: *@This()) void { self.entered_ptr.* += 1; }
        pub fn onLeave(_: *@This()) void {}
    };
    var s = EnterTrack{ .entered_ptr = &entered };
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(EnterTrack, &s));
    // entered = 1 from reset
    r.pop();
    // no onEnter after pop when stack is empty
    try testing.expectEqual(@as(u32, 1), entered);
}

// ============================================================================
// replace()
// ============================================================================

test "ScreenRouter.replace keeps depth at 1" {
    var s1 = NopScreen{};
    var s2 = NopScreen{};
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(NopScreen, &s1));
    try r.replace(ScreenHandle.init(NopScreen, &s2));
    try testing.expectEqual(@as(usize, 1), r.depth());
}

test "ScreenRouter.replace calls onLeave on current, onEnter on new" {
    var log: std.ArrayList(u8) = .empty;
    defer log.deinit(testing.allocator);

    var s1 = LogScreen{ .id = '1', .log_ptr = &log, .alloc = testing.allocator };
    var s2 = LogScreen{ .id = '2', .log_ptr = &log, .alloc = testing.allocator };

    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();

    try r.reset(ScreenHandle.init(LogScreen, &s1));
    log.clearRetainingCapacity();

    try r.replace(ScreenHandle.init(LogScreen, &s2));
    // L1 E2 (leave old, enter new)
    try testing.expectEqualSlices(u8, "L1E2", log.items);
}

test "ScreenRouter.replace on empty stack pushes the new screen" {
    var s = NopScreen{};
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.replace(ScreenHandle.init(NopScreen, &s));
    try testing.expectEqual(@as(usize, 1), r.depth());
}

// ============================================================================
// dispatch()
// ============================================================================

test "ScreenRouter.dispatch cont does not change depth" {
    const ContScreen = struct {
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    var s = ContScreen{};
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(ContScreen, &s));
    try r.dispatch(.{ .key = .{ .code = .enter, .modifiers = .{} } });
    try testing.expectEqual(@as(usize, 1), r.depth());
}

test "ScreenRouter.dispatch pop reduces depth" {
    const PopScreen = struct {
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .pop; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    var s = PopScreen{};
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(PopScreen, &s));
    try r.dispatch(.{ .key = .{ .code = .esc, .modifiers = .{} } });
    try testing.expect(!r.isRunning());
}

test "ScreenRouter.dispatch push increases depth" {
    var s2 = NopScreen{};
    const PushScreen = struct {
        target: *NopScreen,
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(self: *@This(), _: Event) ScreenResult {
            return .{ .push = ScreenHandle.init(NopScreen, self.target) };
        }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    var s1 = PushScreen{ .target = &s2 };
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(PushScreen, &s1));
    try r.dispatch(.{ .key = .{ .code = .enter, .modifiers = .{} } });
    try testing.expectEqual(@as(usize, 2), r.depth());
}

test "ScreenRouter.dispatch replace keeps depth at 1" {
    var s2 = NopScreen{};
    const ReplaceScreen = struct {
        target: *NopScreen,
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(self: *@This(), _: Event) ScreenResult {
            return .{ .replace = ScreenHandle.init(NopScreen, self.target) };
        }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    var s1 = ReplaceScreen{ .target = &s2 };
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(ReplaceScreen, &s1));
    try r.dispatch(.{ .key = .{ .code = .enter, .modifiers = .{} } });
    try testing.expectEqual(@as(usize, 1), r.depth());
}

test "ScreenRouter.dispatch reset clears stack" {
    const ResetScreen = struct {
        do_reset: bool = false,
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(self: *@This(), _: Event) ScreenResult {
            return if (self.do_reset) .reset else .cont;
        }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    var s = ResetScreen{};
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(ResetScreen, &s));
    s.do_reset = true;
    try r.dispatch(.{ .key = .{ .code = .esc, .modifiers = .{} } });
    try testing.expect(!r.isRunning());
}

test "ScreenRouter.dispatch on empty stack is no-op" {
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.dispatch(.{ .key = .{ .code = .enter, .modifiers = .{} } });
    try testing.expect(!r.isRunning());
}

// ============================================================================
// render()
// ============================================================================

test "ScreenRouter.render calls top screen render" {
    var rendered: bool = false;
    const RenderScreen = struct {
        rendered_ptr: *bool,
        pub fn render(self: *@This(), _: *Buffer, _: Rect) void { self.rendered_ptr.* = true; }
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    var s = RenderScreen{ .rendered_ptr = &rendered };
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(RenderScreen, &s));

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    r.render(&buf, area);
    try testing.expect(rendered);
}

test "ScreenRouter.render on empty stack is no-op" {
    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    var buf = try Buffer.init(testing.allocator, 5, 5);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    r.render(&buf, area); // should not crash
}

test "ScreenRouter.render only calls top screen, not screens below" {
    var rendered_bottom: bool = false;
    var rendered_top: bool = false;

    const BottomScreen = struct {
        rendered_ptr: *bool,
        pub fn render(self: *@This(), _: *Buffer, _: Rect) void { self.rendered_ptr.* = true; }
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    const TopScreen = struct {
        rendered_ptr: *bool,
        pub fn render(self: *@This(), _: *Buffer, _: Rect) void { self.rendered_ptr.* = true; }
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };

    var sb = BottomScreen{ .rendered_ptr = &rendered_bottom };
    var st = TopScreen{ .rendered_ptr = &rendered_top };

    var r = ScreenRouter.init(testing.allocator);
    defer r.deinit();
    try r.reset(ScreenHandle.init(BottomScreen, &sb));
    try r.push(ScreenHandle.init(TopScreen, &st));

    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    r.render(&buf, area);

    try testing.expect(!rendered_bottom);
    try testing.expect(rendered_top);
}

// ============================================================================
// deinit()
// ============================================================================

test "ScreenRouter.deinit calls onLeave on all screens top-to-bottom" {
    var log: std.ArrayList(u8) = .empty;
    defer log.deinit(testing.allocator);

    var s1 = LogScreen{ .id = '1', .log_ptr = &log, .alloc = testing.allocator };
    var s2 = LogScreen{ .id = '2', .log_ptr = &log, .alloc = testing.allocator };
    var s3 = LogScreen{ .id = '3', .log_ptr = &log, .alloc = testing.allocator };

    {
        var r = ScreenRouter.init(testing.allocator);
        try r.reset(ScreenHandle.init(LogScreen, &s1));
        try r.push(ScreenHandle.init(LogScreen, &s2));
        try r.push(ScreenHandle.init(LogScreen, &s3));
        log.clearRetainingCapacity();
        r.deinit();
    }
    // deinit: L3 L2 L1 (top to bottom)
    try testing.expectEqualSlices(u8, "L3L2L1", log.items);
}

test "ScreenRouter.deinit on empty router is no-op" {
    var r = ScreenRouter.init(testing.allocator);
    r.deinit(); // should not crash
}
