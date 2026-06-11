//! Timeline Widget Tests — TDD Red Phase
//!
//! Tests timeline widget with event navigation, status markers, direction support,
//! builder pattern, and rendering capabilities.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Timeline = sailor.tui.widgets.Timeline;
const TimelineEvent = sailor.tui.widgets.TimelineEvent;
const TimelineStatus = sailor.tui.widgets.TimelineStatus;
const TimelineDirection = sailor.tui.widgets.TimelineDirection;
const Block = sailor.tui.widgets.Block;

// ============================================================================
// Init Tests (6 tests)
// ============================================================================

test "Timeline.init sets scroll_offset to 0" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "2024-01-15 10:30", .title = "Event 1" },
    };
    const tl = Timeline.init(&events);
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "Timeline.init sets direction to vertical" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "2024-01-15 10:30", .title = "Event 1" },
    };
    const tl = Timeline.init(&events);
    try testing.expectEqual(TimelineDirection.vertical, tl.direction);
}

test "Timeline.init sets show_timestamps to false" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "2024-01-15 10:30", .title = "Event 1" },
    };
    const tl = Timeline.init(&events);
    try testing.expect(tl.show_timestamps == false);
}

test "Timeline.init sets connector_char to '│'" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "2024-01-15 10:30", .title = "Event 1" },
    };
    const tl = Timeline.init(&events);
    try testing.expectEqual(@as(u21, '│'), tl.connector_char);
}

test "Timeline.init with empty events array" {
    var events: [0]TimelineEvent = undefined;
    const tl = Timeline.init(&events);
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
    try testing.expectEqual(@as(usize, 0), tl.events.len);
}

test "Timeline.init borrows events slice" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "Event 1" },
        .{ .timestamp = "T2", .title = "Event 2" },
    };
    const tl = Timeline.init(&events);
    try testing.expectEqual(@as(usize, 2), tl.events.len);
    try testing.expectEqualStrings("Event 1", tl.events[0].title);
    try testing.expectEqualStrings("Event 2", tl.events[1].title);
}

// ============================================================================
// scrollDown Tests (8 tests)
// ============================================================================

test "scrollDown increments scroll_offset" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "Event 1" },
        .{ .timestamp = "T2", .title = "Event 2" },
    };
    var tl = Timeline.init(&events);
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
    tl.scrollDown();
    try testing.expectEqual(@as(usize, 1), tl.scroll_offset);
}

test "scrollDown clamps at last event" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "Event 1" },
        .{ .timestamp = "T2", .title = "Event 2" },
        .{ .timestamp = "T3", .title = "Event 3" },
    };
    var tl = Timeline.init(&events);
    tl.scroll_offset = 2;
    tl.scrollDown();
    try testing.expectEqual(@as(usize, 2), tl.scroll_offset);
}

test "scrollDown on empty events has no effect" {
    var events: [0]TimelineEvent = undefined;
    var tl = Timeline.init(&events);
    tl.scrollDown();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "scrollDown multiple times accumulates" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
        .{ .timestamp = "T3", .title = "E3" },
        .{ .timestamp = "T4", .title = "E4" },
    };
    var tl = Timeline.init(&events);
    tl.scrollDown();
    tl.scrollDown();
    try testing.expectEqual(@as(usize, 2), tl.scroll_offset);
}

test "scrollDown from 0 to 1" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
    };
    var tl = Timeline.init(&events);
    tl.scrollDown();
    try testing.expectEqual(@as(usize, 1), tl.scroll_offset);
}

test "scrollDown to second-to-last event" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
        .{ .timestamp = "T3", .title = "E3" },
    };
    var tl = Timeline.init(&events);
    tl.scrollDown();
    tl.scrollDown();
    try testing.expectEqual(@as(usize, 2), tl.scroll_offset);
}

test "scrollDown single event stays at 0" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    tl.scrollDown();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

// ============================================================================
// scrollUp Tests (6 tests)
// ============================================================================

test "scrollUp decrements scroll_offset" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
    };
    var tl = Timeline.init(&events);
    tl.scroll_offset = 1;
    tl.scrollUp();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "scrollUp clamps at 0" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    tl.scrollUp();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "scrollUp on empty events has no effect" {
    var events: [0]TimelineEvent = undefined;
    var tl = Timeline.init(&events);
    tl.scrollUp();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "scrollUp multiple times from position 3" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
        .{ .timestamp = "T3", .title = "E3" },
        .{ .timestamp = "T4", .title = "E4" },
    };
    var tl = Timeline.init(&events);
    tl.scroll_offset = 3;
    tl.scrollUp();
    tl.scrollUp();
    try testing.expectEqual(@as(usize, 1), tl.scroll_offset);
}

test "scrollUp from 1 goes to 0" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
    };
    var tl = Timeline.init(&events);
    tl.scroll_offset = 1;
    tl.scrollUp();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "scrollUp on single event at 0 stays at 0" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    tl.scrollUp();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

// ============================================================================
// goToTop Tests (4 tests)
// ============================================================================

test "goToTop resets scroll_offset to 0" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
        .{ .timestamp = "T3", .title = "E3" },
    };
    var tl = Timeline.init(&events);
    tl.scroll_offset = 2;
    tl.goToTop();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "goToTop from non-zero position" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
    };
    var tl = Timeline.init(&events);
    tl.scroll_offset = 1;
    tl.goToTop();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "goToTop when already at top" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    tl.goToTop();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "goToTop on empty events" {
    var events: [0]TimelineEvent = undefined;
    var tl = Timeline.init(&events);
    tl.scroll_offset = 5;
    tl.goToTop();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

// ============================================================================
// goToBottom Tests (4 tests)
// ============================================================================

test "goToBottom sets scroll_offset to last event" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
        .{ .timestamp = "T3", .title = "E3" },
    };
    var tl = Timeline.init(&events);
    tl.goToBottom();
    try testing.expectEqual(@as(usize, 2), tl.scroll_offset);
}

test "goToBottom on single event" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    tl.goToBottom();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "goToBottom on empty events stays at 0" {
    var events: [0]TimelineEvent = undefined;
    var tl = Timeline.init(&events);
    tl.scroll_offset = 10;
    tl.goToBottom();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "goToBottom after partial scroll" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
        .{ .timestamp = "T3", .title = "E3" },
        .{ .timestamp = "T4", .title = "E4" },
    };
    var tl = Timeline.init(&events);
    tl.scrollDown();
    tl.scrollDown();
    try testing.expectEqual(@as(usize, 2), tl.scroll_offset);
    tl.goToBottom();
    try testing.expectEqual(@as(usize, 3), tl.scroll_offset);
}

// ============================================================================
// marker() Tests (5 tests)
// ============================================================================

test "marker returns ○ for pending status" {
    const m = Timeline.marker(.pending);
    try testing.expectEqual(@as(u21, '○'), m);
}

test "marker returns ● for active status" {
    const m = Timeline.marker(.active);
    try testing.expectEqual(@as(u21, '●'), m);
}

test "marker returns ✓ for completed status" {
    const m = Timeline.marker(.completed);
    try testing.expectEqual(@as(u21, '✓'), m);
}

test "marker returns ✗ for failed status" {
    const m = Timeline.marker(.failed);
    try testing.expectEqual(@as(u21, '✗'), m);
}

test "marker returns ⊘ for skipped status" {
    const m = Timeline.marker(.skipped);
    try testing.expectEqual(@as(u21, '⊘'), m);
}

// ============================================================================
// Builder Pattern Tests (10 tests)
// ============================================================================

test "withDirection sets direction field" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    const tl2 = tl.withDirection(.horizontal);
    try testing.expectEqual(TimelineDirection.horizontal, tl2.direction);
}

test "withDirection returns Timeline" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    const tl = Timeline.init(&events);
    const tl2 = tl.withDirection(.vertical);
    try testing.expectEqual(@as(u21, '│'), tl2.connector_char);
}

test "withStyle sets style field" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    const custom_style = Style{ .bold = true };
    const tl2 = tl.withStyle(custom_style);
    try testing.expect(tl2.style.bold == true);
}

test "withActiveStyle sets active_style field" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    const custom_style = Style{ .bold = true };
    const tl2 = tl.withActiveStyle(custom_style);
    try testing.expect(tl2.active_style.bold == true);
}

test "withCompletedStyle sets completed_style field" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    const custom_style = Style{ .italic = true };
    const tl2 = tl.withCompletedStyle(custom_style);
    try testing.expect(tl2.completed_style.italic == true);
    try testing.expect(tl2.completed_style.bold == false); // Default bold is false; italic=true confirms the style was actually set
}

test "withFailedStyle sets failed_style field" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    const custom_style = Style{ .bold = true };
    const tl2 = tl.withFailedStyle(custom_style);
    try testing.expect(tl2.failed_style.bold == true);
}

test "withSkippedStyle sets skipped_style field" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    const custom_style = Style{ .bold = true };
    const tl2 = tl.withSkippedStyle(custom_style);
    try testing.expect(tl2.skipped_style.bold == true);
}

test "withShowTimestamps sets show_timestamps field" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    const tl2 = tl.withShowTimestamps(true);
    try testing.expect(tl2.show_timestamps == true);
}

test "withConnectorChar sets connector_char field" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    const tl2 = tl.withConnectorChar('─');
    try testing.expectEqual(@as(u21, '─'), tl2.connector_char);
}

test "withBlock sets block field" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    const block = Block{ .borders = .all };
    const tl2 = tl.withBlock(block);
    try testing.expect(tl2.block != null);
}

// ============================================================================
// Render Tests (8 tests)
// ============================================================================

test "render on zero area does not crash" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    tl.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
}

test "render with empty events does not crash" {
    var events: [0]TimelineEvent = undefined;
    var tl = Timeline.init(&events);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    tl.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "render single event does not crash" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "2024-01-15 10:30", .title = "Event 1" },
    };
    var tl = Timeline.init(&events);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    tl.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "render three events with adequate area" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "Event 1" },
        .{ .timestamp = "T2", .title = "Event 2" },
        .{ .timestamp = "T3", .title = "Event 3" },
    };
    var tl = Timeline.init(&events);
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    tl.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 30 });
}

test "render horizontal direction does not crash" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "Event 1" },
        .{ .timestamp = "T2", .title = "Event 2" },
    };
    var tl = Timeline.init(&events).withDirection(.horizontal);
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();
    tl.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 20 });
}

test "render with show_timestamps true does not crash" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "2024-01-15 10:30", .title = "Event 1" },
    };
    var tl = Timeline.init(&events).withShowTimestamps(true);
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    tl.render(&buf, .{ .x = 0, .y = 0, .width = 50, .height = 20 });
}

test "render narrow area (width=1) does not crash" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "Event 1" },
    };
    var tl = Timeline.init(&events);
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    tl.render(&buf, .{ .x = 0, .y = 0, .width = 1, .height = 10 });
}

test "render with block border does not crash" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "Event 1" },
    };
    const block = Block{ .borders = .all };
    var tl = Timeline.init(&events).withBlock(block);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    tl.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

// ============================================================================
// Edge Cases & Integration Tests (5+ tests)
// ============================================================================

test "scroll past end then goToTop returns to 0" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
    };
    var tl = Timeline.init(&events);
    tl.scrollDown();
    tl.scrollDown();
    tl.scrollDown();
    try testing.expectEqual(@as(usize, 1), tl.scroll_offset);
    tl.goToTop();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "status changes between events" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1", .status = .pending },
        .{ .timestamp = "T2", .title = "E2", .status = .active },
        .{ .timestamp = "T3", .title = "E3", .status = .completed },
    };
    const tl = Timeline.init(&events);
    try testing.expectEqual(TimelineStatus.pending, tl.events[0].status);
    try testing.expectEqual(TimelineStatus.active, tl.events[1].status);
    try testing.expectEqual(TimelineStatus.completed, tl.events[2].status);
}

test "all statuses have markers" {
    try testing.expectEqual(@as(u21, '○'), Timeline.marker(.pending));
    try testing.expectEqual(@as(u21, '●'), Timeline.marker(.active));
    try testing.expectEqual(@as(u21, '✓'), Timeline.marker(.completed));
    try testing.expectEqual(@as(u21, '✗'), Timeline.marker(.failed));
    try testing.expectEqual(@as(u21, '⊘'), Timeline.marker(.skipped));
}

test "scroll with 1 event stays at 0" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    tl.scrollDown();
    tl.scrollDown();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "combined navigation sequence top-bottom-top" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
        .{ .timestamp = "T2", .title = "E2" },
        .{ .timestamp = "T3", .title = "E3" },
    };
    var tl = Timeline.init(&events);
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
    tl.goToBottom();
    try testing.expectEqual(@as(usize, 2), tl.scroll_offset);
    tl.goToTop();
    try testing.expectEqual(@as(usize, 0), tl.scroll_offset);
}

test "builder chaining preserves all fields" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    var tl = Timeline.init(&events);
    const tl2 = tl.withDirection(.horizontal)
        .withShowTimestamps(true)
        .withConnectorChar('─');
    try testing.expectEqual(TimelineDirection.horizontal, tl2.direction);
    try testing.expect(tl2.show_timestamps == true);
    try testing.expectEqual(@as(u21, '─'), tl2.connector_char);
}

test "event with custom description renders" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "Event 1", .description = "This is a detailed description" },
    };
    const tl = Timeline.init(&events);
    try testing.expectEqualStrings("This is a detailed description", tl.events[0].description);
}

test "styles initialized with correct defaults" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "E1" },
    };
    const tl = Timeline.init(&events);
    try testing.expect(tl.active_style.bold == true);
    try testing.expect(tl.completed_style.fg != null);
    try testing.expect(tl.failed_style.fg != null);
}
