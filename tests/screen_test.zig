//! Screen & ScreenHandle Tests — v2.20.0
//!
//! Tests for the Screen abstraction: ScreenHandle type-erasure,
//! ScreenResult variants, and lifecycle hook dispatch.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const ScreenHandle = sailor.ScreenHandle;
const ScreenResult = sailor.ScreenResult;
const Buffer = sailor.Buffer;
const Rect = sailor.Rect;
const Event = sailor.tui.Event;
const KeyEvent = sailor.tui.KeyEvent;
const KeyCode = sailor.tui.KeyCode;

// ============================================================================
// ScreenResult variant tests
// ============================================================================

test "ScreenResult.cont is cont" {
    const r: ScreenResult = .cont;
    try testing.expect(r == .cont);
}

test "ScreenResult.pop is pop" {
    const r: ScreenResult = .pop;
    try testing.expect(r == .pop);
}

test "ScreenResult.reset is reset" {
    const r: ScreenResult = .reset;
    try testing.expect(r == .reset);
}

test "ScreenResult.push carries a ScreenHandle" {
    const NopScreen = struct {
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    var s = NopScreen{};
    const handle = ScreenHandle.init(NopScreen, &s);
    const r: ScreenResult = .{ .push = handle };
    try testing.expect(r == .push);
}

test "ScreenResult.replace carries a ScreenHandle" {
    const NopScreen = struct {
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    var s = NopScreen{};
    const handle = ScreenHandle.init(NopScreen, &s);
    const r: ScreenResult = .{ .replace = handle };
    try testing.expect(r == .replace);
}

// ============================================================================
// ScreenHandle lifecycle dispatch
// ============================================================================

test "ScreenHandle.onEnter calls concrete onEnter" {
    const TrackScreen = struct {
        entered: u32 = 0,
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(self: *@This()) void { self.entered += 1; }
        pub fn onLeave(_: *@This()) void {}
    };
    var s = TrackScreen{};
    const h = ScreenHandle.init(TrackScreen, &s);
    h.onEnter();
    try testing.expectEqual(@as(u32, 1), s.entered);
    h.onEnter();
    try testing.expectEqual(@as(u32, 2), s.entered);
}

test "ScreenHandle.onLeave calls concrete onLeave" {
    const TrackScreen = struct {
        left: u32 = 0,
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(self: *@This()) void { self.left += 1; }
    };
    var s = TrackScreen{};
    const h = ScreenHandle.init(TrackScreen, &s);
    h.onLeave();
    try testing.expectEqual(@as(u32, 1), s.left);
}

test "ScreenHandle.handleEvent returns the screen result" {
    const PopScreen = struct {
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .pop; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    var s = PopScreen{};
    const h = ScreenHandle.init(PopScreen, &s);
    const result = h.handleEvent(.{ .key = .{ .code = .esc, .modifiers = .{} } });
    try testing.expect(result == .pop);
}

test "ScreenHandle.render calls concrete render" {
    const RenderScreen = struct {
        rendered: bool = false,
        pub fn render(self: *@This(), buf: *Buffer, area: Rect) void {
            _ = buf;
            _ = area;
            self.rendered = true;
        }
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    var s = RenderScreen{};
    const h = ScreenHandle.init(RenderScreen, &s);
    var buf = Buffer.init(testing.allocator, 10, 5) catch unreachable;
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    h.render(&buf, area);
    try testing.expect(s.rendered);
}

test "ScreenHandle.handleEvent passes event to screen" {
    const EventCapture = struct {
        last_char: u8 = 0,
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(self: *@This(), event: Event) ScreenResult {
            if (event == .key) {
                if (event.key.code == .char) {
                    self.last_char = event.key.code.char;
                }
            }
            return .cont;
        }
        pub fn onEnter(_: *@This()) void {}
        pub fn onLeave(_: *@This()) void {}
    };
    var s = EventCapture{};
    const h = ScreenHandle.init(EventCapture, &s);
    try testing.expectEqual(@as(u8, 0), s.last_char);
    _ = h.handleEvent(.{ .key = .{ .code = .{ .char = 'z' }, .modifiers = .{} } });
    try testing.expectEqual(@as(u8, 'z'), s.last_char);
}

test "ScreenHandle wraps different screen types independently" {
    const ScreenA = struct {
        val: u32 = 10,
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(self: *@This()) void { self.val += 1; }
        pub fn onLeave(_: *@This()) void {}
    };
    const ScreenB = struct {
        val: u32 = 20,
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .pop; }
        pub fn onEnter(self: *@This()) void { self.val += 2; }
        pub fn onLeave(_: *@This()) void {}
    };

    var sa = ScreenA{};
    var sb = ScreenB{};
    const ha = ScreenHandle.init(ScreenA, &sa);
    const hb = ScreenHandle.init(ScreenB, &sb);

    ha.onEnter();
    hb.onEnter();

    try testing.expectEqual(@as(u32, 11), sa.val);
    try testing.expectEqual(@as(u32, 22), sb.val);

    const ra = ha.handleEvent(.{ .key = .{ .code = .enter, .modifiers = .{} } });
    const rb = hb.handleEvent(.{ .key = .{ .code = .enter, .modifiers = .{} } });
    try testing.expect(ra == .cont);
    try testing.expect(rb == .pop);
}

// ============================================================================
// Lifecycle ordering
// ============================================================================

test "onEnter followed by onLeave tracks order" {
    var log: std.ArrayList([]const u8) = .empty;
    defer log.deinit(testing.allocator);

    const OrderedScreen = struct {
        log_ptr: *std.ArrayList([]const u8),
        pub fn render(_: *@This(), _: *Buffer, _: Rect) void {}
        pub fn handleEvent(_: *@This(), _: Event) ScreenResult { return .cont; }
        pub fn onEnter(self: *@This()) void { self.log_ptr.append(testing.allocator, "enter") catch {}; }
        pub fn onLeave(self: *@This()) void { self.log_ptr.append(testing.allocator, "leave") catch {}; }
    };

    var s = OrderedScreen{ .log_ptr = &log };
    const h = ScreenHandle.init(OrderedScreen, &s);

    h.onEnter();
    h.onEnter();
    h.onLeave();

    try testing.expectEqual(@as(usize, 3), log.items.len);
    try testing.expectEqualStrings("enter", log.items[0]);
    try testing.expectEqualStrings("enter", log.items[1]);
    try testing.expectEqualStrings("leave", log.items[2]);
}
