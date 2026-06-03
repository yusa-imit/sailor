//! Screen abstraction for multi-screen TUI applications.
//!
//! A Screen represents a full-screen "view" with a lifecycle: it can be pushed
//! onto a ScreenRouter stack, rendered each frame, and handle input events.
//! When it is done, it signals how the router should navigate next.
//!
//! ## Design
//! - No vtable/interface — callers use ScreenHandle (type-erased wrapper)
//! - ScreenResult: what the screen wants to do next (continue, push, pop, etc.)
//! - ScreenHandle holds a typed pointer + function table
//! - No allocator in render() — screens own their state
//!
//! ## Usage
//! ```zig
//! const MyScreen = struct {
//!     count: u32 = 0,
//!
//!     pub fn render(self: *@This(), buf: *Buffer, area: Rect) void {
//!         // draw to buf
//!     }
//!
//!     pub fn handleEvent(self: *@This(), event: Event) ScreenResult {
//!         if (event == .key and event.key.code == .char and event.key.code.char == 'q')
//!             return .pop;
//!         return .cont;
//!     }
//!
//!     pub fn onEnter(self: *@This()) void { self.count = 0; }
//!     pub fn onLeave(self: *@This()) void {}
//! };
//! ```

const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;
const Rect = @import("layout.zig").Rect;
const Event = @import("tui.zig").Event;

/// Result returned by Screen.handleEvent to direct navigation.
pub const ScreenResult = union(enum) {
    /// Stay on this screen; render next frame normally.
    cont,

    /// Pop this screen off the stack and return to the previous one.
    pop,

    /// Replace the entire stack with one screen (reset navigation).
    reset,

    /// Push a new screen on top (the current screen is paused but not removed).
    push: ScreenHandle,

    /// Replace this screen with a new one (pop-then-push, no resume of current).
    replace: ScreenHandle,
};

/// Type-erased handle to a concrete screen struct.
/// The caller creates a concrete screen on the stack or heap, then wraps it.
pub const ScreenHandle = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        render: *const fn (ptr: *anyopaque, buf: *Buffer, area: Rect) void,
        handleEvent: *const fn (ptr: *anyopaque, event: Event) ScreenResult,
        onEnter: *const fn (ptr: *anyopaque) void,
        onLeave: *const fn (ptr: *anyopaque) void,
    };

    /// Create a ScreenHandle from a concrete screen pointer.
    /// T must have: render, handleEvent, onEnter, onLeave with correct signatures.
    pub fn init(comptime T: type, ptr: *T) ScreenHandle {
        // Impl is a comptime-unique type per T. Its `vtable` const has static
        // lifetime (placed in rodata), making &Impl.vtable safe to store.
        const Impl = struct {
            pub const vtable: VTable = .{
                .render = renderFn,
                .handleEvent = handleEventFn,
                .onEnter = onEnterFn,
                .onLeave = onLeaveFn,
            };

            fn renderFn(p: *anyopaque, buf: *Buffer, area: Rect) void {
                const self: *T = @alignCast(@ptrCast(p));
                self.render(buf, area);
            }
            fn handleEventFn(p: *anyopaque, event: Event) ScreenResult {
                const self: *T = @alignCast(@ptrCast(p));
                return self.handleEvent(event);
            }
            fn onEnterFn(p: *anyopaque) void {
                const self: *T = @alignCast(@ptrCast(p));
                self.onEnter();
            }
            fn onLeaveFn(p: *anyopaque) void {
                const self: *T = @alignCast(@ptrCast(p));
                self.onLeave();
            }
        };
        return .{ .ptr = ptr, .vtable = &Impl.vtable };
    }

    pub fn render(self: ScreenHandle, buf: *Buffer, area: Rect) void {
        self.vtable.render(self.ptr, buf, area);
    }

    pub fn handleEvent(self: ScreenHandle, event: Event) ScreenResult {
        return self.vtable.handleEvent(self.ptr, event);
    }

    pub fn onEnter(self: ScreenHandle) void {
        self.vtable.onEnter(self.ptr);
    }

    pub fn onLeave(self: ScreenHandle) void {
        self.vtable.onLeave(self.ptr);
    }
};

test "ScreenResult variants" {
    const sr_cont: ScreenResult = .cont;
    const sr_pop: ScreenResult = .pop;
    const sr_reset: ScreenResult = .reset;
    try std.testing.expect(sr_cont == .cont);
    try std.testing.expect(sr_pop == .pop);
    try std.testing.expect(sr_reset == .reset);
}

test "ScreenHandle wraps concrete screen" {
    const TestScreen = struct {
        entered: bool = false,
        left: bool = false,

        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}

        pub fn handleEvent(_: *@This(), _: Event) ScreenResult {
            return .cont;
        }

        pub fn onEnter(self: *@This()) void {
            self.entered = true;
        }

        pub fn onLeave(self: *@This()) void {
            self.left = true;
        }
    };

    var screen = TestScreen{};
    const handle = ScreenHandle.init(TestScreen, &screen);

    handle.onEnter();
    try std.testing.expect(screen.entered);
    try std.testing.expect(!screen.left);

    handle.onLeave();
    try std.testing.expect(screen.left);

    const result = handle.handleEvent(.{ .key = .{ .code = .{ .char = 'a' }, .modifiers = .{} } });
    try std.testing.expect(result == .cont);
}
