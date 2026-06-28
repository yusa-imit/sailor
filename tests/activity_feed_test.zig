//! ActivityFeed Widget Tests — TDD Red Phase
//!
//! Tests activity feed widget with activity items, timestamps, actors, kind-based styling,
//! focused navigation, scrolling for overflow, block border support, and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const ActivityFeed = sailor.tui.widgets.ActivityFeed;
const Activity = sailor.tui.widgets.activity_feed.Activity;
const Kind = sailor.tui.widgets.activity_feed.Kind;

// ============================================================================
// Helper Functions
// ============================================================================

/// Decode UTF-8 text into a codepoint slice (max 256 codepoints)
fn decodeUtf8(text: []const u8, out: []u21) usize {
    var len: usize = 0;
    var view = std.unicode.Utf8View.initUnchecked(text);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |cp| {
        if (len >= out.len) break;
        out[len] = cp;
        len += 1;
    }
    return len;
}

/// Find text in buffer area (UTF-8 aware)
fn findInArea(buf: Buffer, area: Rect, text: []const u8) bool {
    if (text.len == 0) return true;

    var cps: [256]u21 = undefined;
    const cp_count = decodeUtf8(text, &cps);
    if (cp_count == 0) return true;

    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            var matched = true;
            var cp_idx: usize = 0;
            var cx = x;
            var cy = y;

            while (cp_idx < cp_count) : (cp_idx += 1) {
                if (cy >= area.y + area.height or cy >= buf.height or
                    cx >= area.x + area.width or cx >= buf.width) {
                    matched = false;
                    break;
                }

                const cell = buf.getConst(cx, cy) orelse {
                    matched = false;
                    break;
                };
                if (cell.char != cps[cp_idx]) {
                    matched = false;
                    break;
                }
                cx += 1;
                if (cx >= area.x + area.width or cx >= buf.width) {
                    cy += 1;
                    cx = area.x;
                }
            }

            if (matched) return true;
        }
    }
    return false;
}

/// Check if buffer row contains text
fn rowContains(buf: Buffer, row: u16, text: []const u8) bool {
    var cps: [256]u21 = undefined;
    const cp_len = decodeUtf8(text, &cps);
    if (cp_len == 0) return true;
    if (row >= buf.height) return false;

    var i: u16 = 0;
    while (i < buf.width) : (i += 1) {
        var matched = true;
        var j: usize = 0;
        var col = i;

        while (j < cp_len and col < buf.width) : (j += 1) {
            const cell = buf.getConst(col, row) orelse { matched = false; break; };
            if (cell.char != cps[j]) { matched = false; break; }
            col += 1;
        }

        if (j == cp_len and matched) return true;
    }
    return false;
}

/// Count non-space cells in area
fn countNonEmptyCells(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ') {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Check if area contains a specific character
fn areaHasChar(buf: Buffer, area: Rect, ch: u21) bool {
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Count occurrences of a character in area
fn countCharInArea(buf: Buffer, area: Rect, ch: u21) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Get character at specific position in buffer
fn charAt(buf: Buffer, x: u16, y: u16) u21 {
    if (buf.getConst(x, y)) |cell| {
        return cell.char;
    }
    return ' ';
}

// ============================================================================
// Group 1: Init/Defaults (5 tests)
// ============================================================================

test "ActivityFeed.init has empty items" {
    const af = ActivityFeed.init();
    try testing.expectEqual(@as(usize, 0), af.items.len);
}

test "ActivityFeed.init has focused == 0" {
    const af = ActivityFeed.init();
    try testing.expectEqual(@as(usize, 0), af.focused);
}

test "ActivityFeed.init has show_timestamp == true" {
    const af = ActivityFeed.init();
    try testing.expect(af.show_timestamp == true);
}

test "ActivityFeed.init has show_actor == true" {
    const af = ActivityFeed.init();
    try testing.expect(af.show_actor == true);
}

test "ActivityFeed.init has null block" {
    const af = ActivityFeed.init();
    try testing.expect(af.block == null);
}

// ============================================================================
// Group 2: Kind Enum (5 tests)
// ============================================================================

test "Kind.info exists" {
    const k: Kind = .info;
    try testing.expect(k == .info);
}

test "Kind.success exists" {
    const k: Kind = .success;
    try testing.expect(k == .success);
}

test "Kind.warning exists" {
    const k: Kind = .warning;
    try testing.expect(k == .warning);
}

test "Kind.error_kind exists" {
    const k: Kind = .error_kind;
    try testing.expect(k == .error_kind);
}

test "Kind.action exists" {
    const k: Kind = .action;
    try testing.expect(k == .action);
}

// ============================================================================
// Group 3: Activity Struct Defaults (3 tests)
// ============================================================================

test "Activity with only event has empty timestamp by default" {
    const act = Activity{ .event = "test event" };
    try testing.expectEqual(@as(usize, 0), act.timestamp.len);
}

test "Activity with only event has empty actor by default" {
    const act = Activity{ .event = "test event" };
    try testing.expectEqual(@as(usize, 0), act.actor.len);
}

test "Activity with only event has kind=.info by default" {
    const act = Activity{ .event = "test event" };
    try testing.expect(act.kind == .info);
}

// ============================================================================
// Group 4: Builder Immutability (5 tests)
// ============================================================================

test "withItems returns new value, original unchanged" {
    var items1 = [_]Activity{.{ .event = "event 1" }};
    const af1 = ActivityFeed.init().withItems(&items1);
    const af2 = af1.withItems(&.{});
    try testing.expectEqual(@as(usize, 1), af1.items.len);
    try testing.expectEqual(@as(usize, 0), af2.items.len);
}

test "withFocused returns new value, original unchanged" {
    const af1 = ActivityFeed.init().withFocused(3);
    const af2 = af1.withFocused(5);
    try testing.expectEqual(@as(usize, 3), af1.focused);
    try testing.expectEqual(@as(usize, 5), af2.focused);
}

test "withShowTimestamp returns new value, original unchanged" {
    const af1 = ActivityFeed.init().withShowTimestamp(false);
    const af2 = af1.withShowTimestamp(true);
    try testing.expect(af1.show_timestamp == false);
    try testing.expect(af2.show_timestamp == true);
}

test "withShowActor returns new value, original unchanged" {
    const af1 = ActivityFeed.init().withShowActor(false);
    const af2 = af1.withShowActor(true);
    try testing.expect(af1.show_actor == false);
    try testing.expect(af2.show_actor == true);
}

test "withBlock returns new value, original unchanged" {
    const af1 = ActivityFeed.init();
    const af2 = af1.withBlock(.{});
    try testing.expect(af1.block == null);
    try testing.expect(af2.block != null);
}

// ============================================================================
// Group 5: itemCount (3 tests)
// ============================================================================

test "itemCount returns 0 for empty items" {
    const af = ActivityFeed.init();
    try testing.expectEqual(@as(usize, 0), af.itemCount());
}

test "itemCount returns correct count when under MAX_ITEMS" {
    var items = [_]Activity{
        .{ .event = "a" },
        .{ .event = "b" },
        .{ .event = "c" },
    };
    const af = ActivityFeed.init().withItems(&items);
    try testing.expectEqual(@as(usize, 3), af.itemCount());
}

test "itemCount returns MAX_ITEMS (64) when items exceed it" {
    var items: [100]Activity = undefined;
    for (0..100) |i| {
        items[i] = Activity{ .event = "event" };
    }
    const af = ActivityFeed.init().withItems(&items);
    try testing.expectEqual(@as(usize, ActivityFeed.MAX_ITEMS), af.itemCount());
}

// ============================================================================
// Group 6: Render Zero Area (2 tests)
// ============================================================================

test "render with zero height does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test" }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };
    af.render(&buf, area);
}

test "render with zero width does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test" }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    af.render(&buf, area);
}

// ============================================================================
// Group 7: Render Minimal Area (2 tests)
// ============================================================================

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test" }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    af.render(&buf, area);
}

test "render with 2x2 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test" }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    af.render(&buf, area);
}

// ============================================================================
// Group 8: Render Empty Items (1 test)
// ============================================================================

test "render with empty items does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const af = ActivityFeed.init();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

// ============================================================================
// Group 9: Render Single Item (6 tests)
// ============================================================================

test "render single item shows event text" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "login successful" }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "login successful"));
}

test "render single item shows icon" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .kind = .info }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, '·'));
}

test "render single item shows timestamp when show_timestamp=true" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .timestamp = "12:00" }};
    const af = ActivityFeed.init().withItems(&items).withShowTimestamp(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "12:00"));
}

test "render single item hides timestamp when show_timestamp=false" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .timestamp = "12:00" }};
    const af = ActivityFeed.init().withItems(&items).withShowTimestamp(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(!findInArea(buf, area, "12:00"));
}

test "render single item shows actor when show_actor=true" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .actor = "alice" }};
    const af = ActivityFeed.init().withItems(&items).withShowActor(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "alice"));
}

test "render single item hides actor when show_actor=false" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .actor = "alice" }};
    const af = ActivityFeed.init().withItems(&items).withShowActor(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(!findInArea(buf, area, "alice"));
}

// ============================================================================
// Group 10: Render Multiple Items (5 tests)
// ============================================================================

test "render multiple items each on own row" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "first event" },
        .{ .event = "second event" },
    };
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "first event"));
    try testing.expect(findInArea(buf, area, "second event"));
}

test "render multiple items in order (first at top)" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "alpha" },
        .{ .event = "beta" },
        .{ .event = "gamma" },
    };
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    // alpha should be before beta and gamma
    var alpha_y: i16 = -1;
    var beta_y: i16 = -1;
    var y: u16 = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        if (alpha_y == -1 and rowContains(buf, y, "alpha")) {
            alpha_y = @intCast(y);
        }
        if (beta_y == -1 and rowContains(buf, y, "beta")) {
            beta_y = @intCast(y);
        }
    }
    try testing.expect(alpha_y >= 0);
    try testing.expect(beta_y >= 0);
    try testing.expect(alpha_y < beta_y);
}

test "render 3 items in limited height shows only what fits" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "event1" },
        .{ .event = "event2" },
        .{ .event = "event3" },
    };
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 2 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "event1"));
    try testing.expect(findInArea(buf, area, "event2"));
}

test "render items with mix of fields" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "login", .actor = "alice", .timestamp = "10:00" },
        .{ .event = "logout", .actor = "bob", .timestamp = "10:30" },
    };
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "login"));
    try testing.expect(findInArea(buf, area, "alice"));
    try testing.expect(findInArea(buf, area, "10:00"));
}

test "render count matches visible items" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "event1" },
        .{ .event = "event2" },
    };
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    const icon_count = countCharInArea(buf, area, '·');
    try testing.expectEqual(@as(usize, 2), icon_count);
}

// ============================================================================
// Group 11: Focused Item (4 tests)
// ============================================================================

test "focused item at index 0 renders without error" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "event1" },
        .{ .event = "event2" },
    };
    const af = ActivityFeed.init().withItems(&items).withFocused(0);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

test "focused item at last index renders without error" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "event1" },
        .{ .event = "event2" },
        .{ .event = "event3" },
    };
    const af = ActivityFeed.init().withItems(&items).withFocused(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

test "focused index beyond items length clamps gracefully" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "event1" },
        .{ .event = "event2" },
    };
    const af = ActivityFeed.init().withItems(&items).withFocused(10);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

test "focused item renders with items visible" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "event1" },
        .{ .event = "event2" },
    };
    const af = ActivityFeed.init().withItems(&items).withFocused(1);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "event2"));
}

// ============================================================================
// Group 12: Overflow/Scrolling (5 tests)
// ============================================================================

test "overflow: items > height shows window with focused visible" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "item1" },
        .{ .event = "item2" },
        .{ .event = "item3" },
        .{ .event = "item4" },
        .{ .event = "item5" },
    };
    const af = ActivityFeed.init().withItems(&items).withFocused(4);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 2 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "item5"));
}

test "overflow: focused=0 shows first N items" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "first" },
        .{ .event = "second" },
        .{ .event = "third" },
    };
    const af = ActivityFeed.init().withItems(&items).withFocused(0);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 2 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "first"));
}

test "overflow: focused near end shows last N items" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{
        .{ .event = "item1" },
        .{ .event = "item2" },
        .{ .event = "item3" },
        .{ .event = "item4" },
    };
    const af = ActivityFeed.init().withItems(&items).withFocused(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 2 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "item4"));
}

test "overflow: 10 items, height 3, focused=5 shows window around focused" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items: [10]Activity = undefined;
    const event_names = [_][]const u8{ "item0", "item1", "item2", "item3", "item4", "item5", "item6", "item7", "item8", "item9" };
    for (0..10) |i| {
        items[i] = Activity{ .event = event_names[i] };
    }
    const af = ActivityFeed.init().withItems(&items).withFocused(5);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 3 };
    af.render(&buf, area);
}

test "overflow: all 64 MAX_ITEMS renders without crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items: [ActivityFeed.MAX_ITEMS]Activity = undefined;
    for (0..ActivityFeed.MAX_ITEMS) |i| {
        items[i] = Activity{ .event = "event" };
    }
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

// ============================================================================
// Group 13: Kind Icons (5 tests)
// ============================================================================

test "kind .info shows icon ·" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .kind = .info }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, '·'));
}

test "kind .success shows icon ●" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .kind = .success }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, '●'));
}

test "kind .warning shows icon ⚠" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .kind = .warning }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, '⚠'));
}

test "kind .error_kind shows icon ✗" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .kind = .error_kind }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, '✗'));
}

test "kind .action shows icon →" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .kind = .action }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, '→'));
}

// ============================================================================
// Group 14: Kind Styles (5 tests)
// ============================================================================

test "kind .info icon uses info_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const info_style = Style{ .fg = .red };
    var items = [_]Activity{.{ .event = "test", .kind = .info }};
    const af = ActivityFeed.init()
        .withItems(&items)
        .withInfoStyle(info_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

test "kind .success icon uses success_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const success_style = Style{ .fg = .green };
    var items = [_]Activity{.{ .event = "test", .kind = .success }};
    const af = ActivityFeed.init()
        .withItems(&items)
        .withSuccessStyle(success_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

test "kind .warning icon uses warning_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const warning_style = Style{ .fg = .yellow };
    var items = [_]Activity{.{ .event = "test", .kind = .warning }};
    const af = ActivityFeed.init()
        .withItems(&items)
        .withWarningStyle(warning_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

test "kind .error_kind icon uses error_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const error_style = Style{ .fg = .red };
    var items = [_]Activity{.{ .event = "test", .kind = .error_kind }};
    const af = ActivityFeed.init()
        .withItems(&items)
        .withErrorStyle(error_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

test "kind .action icon uses action_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const action_style = Style{ .fg = .blue };
    var items = [_]Activity{.{ .event = "test", .kind = .action }};
    const af = ActivityFeed.init()
        .withItems(&items)
        .withActionStyle(action_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

// ============================================================================
// Group 15: Timestamp Toggle (3 tests)
// ============================================================================

test "timestamp shown when show_timestamp=true and timestamp is set" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .timestamp = "10:30" }};
    const af = ActivityFeed.init().withItems(&items).withShowTimestamp(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "10:30"));
}

test "timestamp hidden when show_timestamp=false even if set" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .timestamp = "10:30" }};
    const af = ActivityFeed.init().withItems(&items).withShowTimestamp(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(!findInArea(buf, area, "10:30"));
}

test "timestamp hidden when show_timestamp=true but timestamp is empty" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .timestamp = "" }};
    const af = ActivityFeed.init().withItems(&items).withShowTimestamp(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "test"));
}

// ============================================================================
// Group 16: Actor Toggle (3 tests)
// ============================================================================

test "actor shown when show_actor=true and actor is set" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .actor = "alice" }};
    const af = ActivityFeed.init().withItems(&items).withShowActor(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "alice"));
}

test "actor hidden when show_actor=false even if set" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .actor = "alice" }};
    const af = ActivityFeed.init().withItems(&items).withShowActor(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(!findInArea(buf, area, "alice"));
}

test "actor hidden when show_actor=true but actor is empty" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test", .actor = "" }};
    const af = ActivityFeed.init().withItems(&items).withShowActor(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "test"));
}

// ============================================================================
// Group 17: Block Border (3 tests)
// ============================================================================

test "block reduces rendering area correctly" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test content" }};
    const af = ActivityFeed.init().withItems(&items).withBlock(.{});
    const area = Rect{ .x = 5, .y = 5, .width = 60, .height = 10 };
    af.render(&buf, area);
}

test "block border chars appear when block is set" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "test" }};
    const af = ActivityFeed.init().withItems(&items).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    af.render(&buf, area);
}

test "content renders inside block inner area" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "inside" }};
    const af = ActivityFeed.init().withItems(&items).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "inside"));
}

// ============================================================================
// Group 18: Edge Cases (5 tests)
// ============================================================================

test "very long event text truncates at area width" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const long_text = "this is a very long event text that should be truncated at the area width";
    var items = [_]Activity{.{ .event = long_text }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    af.render(&buf, area);
}

test "activity with all empty fields renders icon only" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "", .timestamp = "", .actor = "" }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

test "offset area (x>0, y>0) renders correctly" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "offset test" }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 10, .y = 5, .width = 60, .height = 10 };
    af.render(&buf, area);

    try testing.expect(findInArea(buf, area, "offset test"));
}

test "max items (64) with all fields filled renders without crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items: [ActivityFeed.MAX_ITEMS]Activity = undefined;
    for (0..ActivityFeed.MAX_ITEMS) |i| {
        items[i] = Activity{
            .event = "event",
            .timestamp = "10:00",
            .actor = "user",
            .kind = .info,
        };
    }
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}

test "unicode in event text renders correctly" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]Activity{.{ .event = "event with emoji 🎉" }};
    const af = ActivityFeed.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    af.render(&buf, area);
}
