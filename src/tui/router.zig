//! ScreenRouter — stack-based screen navigation for multi-screen TUI apps.
//!
//! Manages a stack of ScreenHandles. The top-of-stack screen receives events
//! and is rendered each frame. Navigation is driven by the ScreenResult returned
//! by handleEvent().
//!
//! ## Navigation model
//! - push   → pause current screen, activate new screen on top
//! - pop    → leave current screen, resume the one beneath
//! - reset  → clear stack, activate a new root screen
//! - replace → leave current screen, push replacement (no resume)
//! - cont   → stay on current screen
//!
//! ## Lifecycle
//! Each screen gets `onEnter()` when it becomes the active top-of-stack,
//! and `onLeave()` when it is suspended (push above it) or removed (pop/replace).
//!
//! ## Allocator usage
//! ScreenRouter stores the allocator for the stack backing array.
//! Screen structs themselves are allocated by the caller.
//!
//! ## Usage
//! ```zig
//! var router = ScreenRouter.init(allocator);
//! defer router.deinit();
//!
//! try router.reset(ScreenHandle.init(MainScreen, &main_screen));
//!
//! while (router.isRunning()) {
//!     try term.draw(struct {
//!         fn render(f: *Frame) !void {
//!             router.render(f.buffer(), f.area());
//!         }
//!     }.render);
//!     if (try term.pollEvent()) |event| {
//!         try router.dispatch(event);
//!     }
//! }
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("buffer.zig").Buffer;
const Rect = @import("layout.zig").Rect;
const screen_mod = @import("screen.zig");
const ScreenHandle = screen_mod.ScreenHandle;
const ScreenResult = screen_mod.ScreenResult;
const Event = @import("tui.zig").Event;

/// Stack-based screen router.
pub const ScreenRouter = struct {
    allocator: Allocator,
    stack: std.ArrayList(ScreenHandle),

    pub fn init(allocator: Allocator) ScreenRouter {
        return .{ .allocator = allocator, .stack = .empty };
    }

    pub fn deinit(self: *ScreenRouter) void {
        // Call onLeave on all screens still in stack (from top to bottom)
        var i = self.stack.items.len;
        while (i > 0) {
            i -= 1;
            self.stack.items[i].onLeave();
        }
        self.stack.deinit(self.allocator);
    }

    /// Returns true when there is at least one screen on the stack.
    pub fn isRunning(self: *const ScreenRouter) bool {
        return self.stack.items.len > 0;
    }

    /// Depth of the navigation stack.
    pub fn depth(self: *const ScreenRouter) usize {
        return self.stack.items.len;
    }

    /// Clear the stack and push a new root screen.
    /// All existing screens get onLeave() called (top to bottom).
    pub fn reset(self: *ScreenRouter, handle: ScreenHandle) !void {
        var i = self.stack.items.len;
        while (i > 0) {
            i -= 1;
            self.stack.items[i].onLeave();
        }
        self.stack.clearRetainingCapacity();
        try self.stack.append(self.allocator, handle);
        handle.onEnter();
    }

    /// Push a new screen on top without removing the current one.
    /// The current screen gets onLeave(), the new screen gets onEnter().
    pub fn push(self: *ScreenRouter, handle: ScreenHandle) !void {
        if (self.stack.items.len > 0) {
            self.stack.items[self.stack.items.len - 1].onLeave();
        }
        try self.stack.append(self.allocator, handle);
        handle.onEnter();
    }

    /// Pop the top screen off the stack.
    /// The popped screen gets onLeave(), the one beneath (if any) gets onEnter().
    pub fn pop(self: *ScreenRouter) void {
        if (self.stack.items.len == 0) return;
        const top = self.stack.pop().?;
        top.onLeave();
        if (self.stack.items.len > 0) {
            self.stack.items[self.stack.items.len - 1].onEnter();
        }
    }

    /// Replace the top screen with a new one.
    /// Current screen gets onLeave(), new screen gets onEnter().
    pub fn replace(self: *ScreenRouter, handle: ScreenHandle) !void {
        if (self.stack.items.len > 0) {
            const top = self.stack.pop().?;
            top.onLeave();
        }
        try self.stack.append(self.allocator, handle);
        handle.onEnter();
    }

    /// Render the top-of-stack screen into the buffer.
    /// No-op if the stack is empty.
    pub fn render(self: *const ScreenRouter, buf: *Buffer, area: Rect) void {
        if (self.stack.items.len == 0) return;
        self.stack.items[self.stack.items.len - 1].render(buf, area);
    }

    /// Dispatch an event to the top-of-stack screen and apply navigation.
    /// Returns an error if a push/replace/reset allocation fails.
    pub fn dispatch(self: *ScreenRouter, event: Event) !void {
        if (self.stack.items.len == 0) return;
        const result = self.stack.items[self.stack.items.len - 1].handleEvent(event);
        switch (result) {
            .cont => {},
            .pop => self.pop(),
            .reset => {
                // Stack is empty after reset with no new screen — caller is responsible
                // for resetting with a screen. Here we just clear.
                var i = self.stack.items.len;
                while (i > 0) {
                    i -= 1;
                    self.stack.items[i].onLeave();
                }
                self.stack.clearRetainingCapacity();
            },
            .push => |handle| try self.push(handle),
            .replace => |handle| try self.replace(handle),
        }
    }
};

test "ScreenRouter.init and isRunning" {
    var router = ScreenRouter.init(std.testing.allocator);
    defer router.deinit();
    try std.testing.expect(!router.isRunning());
    try std.testing.expectEqual(@as(usize, 0), router.depth());
}

test "ScreenRouter.reset pushes root and calls onEnter" {
    var entered: u32 = 0;
    var left: u32 = 0;

    const TrackScreen = struct {
        entered_ptr: *u32,
        left_ptr: *u32,

        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(self: *@This()) void { self.entered_ptr.* += 1; }
        pub fn onLeave(self: *@This()) void { self.left_ptr.* += 1; }
    };

    var screen = TrackScreen{ .entered_ptr = &entered, .left_ptr = &left };
    var router = ScreenRouter.init(std.testing.allocator);
    defer router.deinit();

    try router.reset(ScreenHandle.init(TrackScreen, &screen));
    try std.testing.expect(router.isRunning());
    try std.testing.expectEqual(@as(usize, 1), router.depth());
    try std.testing.expectEqual(@as(u32, 1), entered);
    try std.testing.expectEqual(@as(u32, 0), left);
}

test "ScreenRouter.push and pop lifecycle" {
    const alloc = std.testing.allocator;
    var log: std.ArrayList(u8) = .empty;
    defer log.deinit(alloc);

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

    var s1 = LogScreen{ .id = '1', .log_ptr = &log, .alloc = alloc };
    var s2 = LogScreen{ .id = '2', .log_ptr = &log, .alloc = alloc };

    var router = ScreenRouter.init(alloc);
    defer router.deinit();

    try router.reset(ScreenHandle.init(LogScreen, &s1));
    try std.testing.expectEqualSlices(u8, "E1", log.items);

    try router.push(ScreenHandle.init(LogScreen, &s2));
    try std.testing.expectEqualSlices(u8, "E1L1E2", log.items);
    try std.testing.expectEqual(@as(usize, 2), router.depth());

    router.pop();
    try std.testing.expectEqualSlices(u8, "E1L1E2L2E1", log.items);
    try std.testing.expectEqual(@as(usize, 1), router.depth());

    router.pop();
    try std.testing.expectEqualSlices(u8, "E1L1E2L2E1L1", log.items);
    try std.testing.expect(!router.isRunning());
}

test "ScreenRouter.replace lifecycle" {
    const alloc = std.testing.allocator;
    var log: std.ArrayList(u8) = .empty;
    defer log.deinit(alloc);

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

    var s1 = LogScreen{ .id = '1', .log_ptr = &log, .alloc = alloc };
    var s2 = LogScreen{ .id = '2', .log_ptr = &log, .alloc = alloc };

    var router = ScreenRouter.init(alloc);
    defer router.deinit();

    try router.reset(ScreenHandle.init(LogScreen, &s1));
    try router.replace(ScreenHandle.init(LogScreen, &s2));
    try std.testing.expectEqualSlices(u8, "E1L1E2", log.items);
    try std.testing.expectEqual(@as(usize, 1), router.depth());
}

test "ScreenRouter.dispatch routes ScreenResult" {
    const DecisionScreen = struct {
        result: ScreenResult,

        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(self: *@This(), _: Event) ScreenResult { return self.result; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };

    var s1 = DecisionScreen{ .result = .cont };
    var s2 = DecisionScreen{ .result = .cont };

    var router = ScreenRouter.init(std.testing.allocator);
    defer router.deinit();

    try router.reset(ScreenHandle.init(DecisionScreen, &s1));
    try std.testing.expectEqual(@as(usize, 1), router.depth());

    try router.dispatch(.{ .key = .{ .code = .{ .char = 'a' }, .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 1), router.depth());

    s1.result = .{ .push = ScreenHandle.init(DecisionScreen, &s2) };
    try router.dispatch(.{ .key = .{ .code = .{ .char = 'b' }, .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 2), router.depth());

    s2.result = .pop;
    try router.dispatch(.{ .key = .{ .code = .{ .char = 'c' }, .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 1), router.depth());
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

    var s1 = ResetScreen{};
    var router = ScreenRouter.init(std.testing.allocator);
    defer router.deinit();

    try router.reset(ScreenHandle.init(ResetScreen, &s1));
    try std.testing.expectEqual(@as(usize, 1), router.depth());

    s1.do_reset = true;
    try router.dispatch(.{ .key = .{ .code = .{ .char = 'q' }, .modifiers = .{} } });
    try std.testing.expect(!router.isRunning());
}

test "ScreenRouter.deinit calls onLeave on all screens" {
    var left: u32 = 0;

    const LeaveScreen = struct {
        left_ptr: *u32,

        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(self: *@This()) void { self.left_ptr.* += 1; }
    };

    var s1 = LeaveScreen{ .left_ptr = &left };
    var s2 = LeaveScreen{ .left_ptr = &left };

    {
        var router = ScreenRouter.init(std.testing.allocator);
        try router.reset(ScreenHandle.init(LeaveScreen, &s1));
        // manually push s2 without going through push (to avoid onLeave s1)
        try router.stack.append(router.allocator, ScreenHandle.init(LeaveScreen, &s2));
        // deinit should call onLeave on both
        router.deinit();
    }
    try std.testing.expectEqual(@as(u32, 2), left);
}
