//! ToggleSwitch Widget Tests — TDD Red Phase
//!
//! Tests ToggleSwitch widget (boolean on/off slider-style control) and ToggleSwitchGroup.
//! Tests cover:
//! - Initialization defaults (checked=false, disabled=false, focused=false)
//! - Default labels: on_label="ON", off_label="OFF"
//! - Builder immutability: each withX method returns new value without mutating original
//! - toggle() flips checked state; no-op when disabled=true
//! - Rendering: fixed track width=6 cells, knob at left (◯) when off, right (◉) when on
//! - Label rendering: one space after track, then label text (truncated if needed)
//! - Style precedence: base = on_style if checked else off_style; disabled_style overrides if disabled=true; focused_style overrides if focused=true and not disabled
//! - Edge cases: area.width < 7, area.height == 0, zero-width area (must not panic)
//! - ToggleSwitchGroup: focusedItem(), focusNext(), focusPrev() with wrap-around
//! - focusNext/focusPrev skip disabled items when possible
//! - toggleFocused() no-op when focused item is disabled
//! - render() lays out one switch per row, respects optional Block border

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const ToggleSwitch = sailor.tui.widgets.ToggleSwitch;
const ToggleSwitchGroup = sailor.tui.widgets.ToggleSwitchGroup;

// ============================================================================
// Group 1: ToggleSwitch Init and Defaults
// ============================================================================

test "ToggleSwitch.init creates with default label only" {
    const ts = ToggleSwitch.init("Test Label");
    try testing.expectEqualStrings("Test Label", ts.label);
}

test "ToggleSwitch.init defaults checked to false" {
    const ts = ToggleSwitch.init("Toggle me");
    try testing.expect(!ts.checked);
}

test "ToggleSwitch.init defaults disabled to false" {
    const ts = ToggleSwitch.init("Toggle me");
    try testing.expect(!ts.disabled);
}

test "ToggleSwitch.init defaults focused to false" {
    const ts = ToggleSwitch.init("Toggle me");
    try testing.expect(!ts.focused);
}

test "ToggleSwitch.init defaults on_label to ON" {
    const ts = ToggleSwitch.init("Toggle me");
    try testing.expectEqualStrings("ON", ts.on_label);
}

test "ToggleSwitch.init defaults off_label to OFF" {
    const ts = ToggleSwitch.init("Toggle me");
    try testing.expectEqualStrings("OFF", ts.off_label);
}

test "ToggleSwitch.init defaults style to empty Style" {
    const ts = ToggleSwitch.init("Toggle me");
    try testing.expectEqual(Style{}, ts.style);
}

test "ToggleSwitch.init defaults on_style to empty Style" {
    const ts = ToggleSwitch.init("Toggle me");
    try testing.expectEqual(Style{}, ts.on_style);
}

test "ToggleSwitch.init defaults off_style to empty Style" {
    const ts = ToggleSwitch.init("Toggle me");
    try testing.expectEqual(Style{}, ts.off_style);
}

test "ToggleSwitch.init defaults focused_style to empty Style" {
    const ts = ToggleSwitch.init("Toggle me");
    try testing.expectEqual(Style{}, ts.focused_style);
}

test "ToggleSwitch.init defaults disabled_style to empty Style" {
    const ts = ToggleSwitch.init("Toggle me");
    try testing.expectEqual(Style{}, ts.disabled_style);
}

// ============================================================================
// Group 2: ToggleSwitch Builder Immutability
// ============================================================================

test "withChecked does not modify original" {
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withChecked(true);
    try testing.expect(!ts1.checked);
    try testing.expect(ts2.checked);
}

test "withDisabled does not modify original" {
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withDisabled(true);
    try testing.expect(!ts1.disabled);
    try testing.expect(ts2.disabled);
}

test "withFocus does not modify original" {
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withFocus(true);
    try testing.expect(!ts1.focused);
    try testing.expect(ts2.focused);
}

test "withLabels does not modify original" {
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withLabels("YES", "NO");
    try testing.expectEqualStrings("ON", ts1.on_label);
    try testing.expectEqualStrings("OFF", ts1.off_label);
    try testing.expectEqualStrings("YES", ts2.on_label);
    try testing.expectEqualStrings("NO", ts2.off_label);
}

test "withStyle does not modify original" {
    const style1 = Style{ .fg = .red };
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withStyle(style1);
    try testing.expectEqual(Style{}, ts1.style);
    try testing.expectEqual(style1, ts2.style);
}

test "withOnStyle does not modify original" {
    const style1 = Style{ .fg = .green };
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withOnStyle(style1);
    try testing.expectEqual(Style{}, ts1.on_style);
    try testing.expectEqual(style1, ts2.on_style);
}

test "withOffStyle does not modify original" {
    const style1 = Style{ .fg = .gray };
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withOffStyle(style1);
    try testing.expectEqual(Style{}, ts1.off_style);
    try testing.expectEqual(style1, ts2.off_style);
}

test "withFocusedStyle does not modify original" {
    const style1 = Style{ .bold = true };
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withFocusedStyle(style1);
    try testing.expectEqual(Style{}, ts1.focused_style);
    try testing.expectEqual(style1, ts2.focused_style);
}

test "withDisabledStyle does not modify original" {
    const style1 = Style{ .dim = true };
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withDisabledStyle(style1);
    try testing.expectEqual(Style{}, ts1.disabled_style);
    try testing.expectEqual(style1, ts2.disabled_style);
}

// ============================================================================
// Group 3: ToggleSwitch toggle() Behavior
// ============================================================================

test "toggle flips checked from false to true" {
    var ts = ToggleSwitch.init("Toggle");
    try testing.expect(!ts.checked);
    ts.toggle();
    try testing.expect(ts.checked);
}

test "toggle flips checked from true to false" {
    var ts = ToggleSwitch.init("Toggle").withChecked(true);
    try testing.expect(ts.checked);
    ts.toggle();
    try testing.expect(!ts.checked);
}

test "toggle is no-op when disabled" {
    var ts = ToggleSwitch.init("Toggle").withDisabled(true).withChecked(false);
    ts.toggle();
    try testing.expect(!ts.checked);
}

test "toggle is no-op when disabled even if checked" {
    var ts = ToggleSwitch.init("Toggle").withDisabled(true).withChecked(true);
    ts.toggle();
    try testing.expect(ts.checked);
}

// ============================================================================
// Group 4: ToggleSwitch Rendering - Track and Knob
// ============================================================================

test "render off-state shows knob at left position (◯)" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();

    const ts = ToggleSwitch.init("Test").withChecked(false);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    ts.render(&buf, area);

    // Track starts at x=0, knob at left (x=1) should be '◯'
    const knob_cell = buf.getConst(1, 0);
    try testing.expect(knob_cell != null);
    try testing.expectEqual('◯', knob_cell.?.char);
}

test "render on-state shows knob at right position (◉)" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();

    const ts = ToggleSwitch.init("Test").withChecked(true);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    ts.render(&buf, area);

    // Track starts at x=0, knob at right (x=5) should be '◉'
    const knob_cell = buf.getConst(5, 0);
    try testing.expect(knob_cell != null);
    try testing.expectEqual('◉', knob_cell.?.char);
}

test "render track width is exactly 6 cells" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();

    const ts = ToggleSwitch.init("Test");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    ts.render(&buf, area);

    // Track cells at x=0..5 should be '[', space/knob, space, space, space, ']'
    // Verify x=0 is '[' and x=6 is space (label separator)
    const left_bracket = buf.getConst(0, 0);
    const right_bracket = buf.getConst(6, 0);
    try testing.expect(left_bracket != null);
    try testing.expectEqual('[', left_bracket.?.char);
    try testing.expect(right_bracket != null);
    try testing.expectEqual(' ', right_bracket.?.char); // space separator after track
}

// ============================================================================
// Group 5: ToggleSwitch Rendering - Labels
// ============================================================================

test "render label appears after track and space separator" {
    var buf = try Buffer.init(testing.allocator, 30, 1);
    defer buf.deinit();

    const ts = ToggleSwitch.init("MyLabel");
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    ts.render(&buf, area);

    // Track: x=0-6 ('[' at 0, knob at 1-5, ']' at 6)
    // Space: x=7
    // Label starts at x=8
    const label_start = buf.getConst(8, 0);
    try testing.expect(label_start != null);
    try testing.expectEqual('M', label_start.?.char);
}

test "render truncates label when area too narrow" {
    var buf = try Buffer.init(testing.allocator, 15, 1);
    defer buf.deinit();

    const ts = ToggleSwitch.init("VeryLongLabelText");
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 1 };
    ts.render(&buf, area);

    // Track=7 chars, separator=1, leaves 15-8=7 chars for label
    // Label should be "VeryLon" (7 chars)
    var label_buf: [10]u8 = undefined;
    for (0..7) |i| {
        const cell = buf.getConst(8 + @as(u16, @intCast(i)), 0);
        if (cell) |c| {
            label_buf[i] = @intCast(c.char);
        }
    }
    try testing.expectEqualStrings("VeryLon", label_buf[0..7]);
}

test "render zero-length label renders only track" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const ts = ToggleSwitch.init("");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    ts.render(&buf, area);

    // Only track and separator should render
    const track = buf.getConst(0, 0);
    try testing.expect(track != null);
    try testing.expectEqual('[', track.?.char);
}

// ============================================================================
// Group 6: ToggleSwitch Style Precedence
// ============================================================================

test "style precedence: off_style when checked=false" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const off_style = Style{ .fg = .gray };
    const ts = ToggleSwitch.init("Test")
        .withChecked(false)
        .withOffStyle(off_style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    ts.render(&buf, area);

    // Knob at x=1 should have off_style
    const knob_cell = buf.getConst(1, 0);
    try testing.expect(knob_cell != null);
    try testing.expectEqual(off_style, knob_cell.?.style);
}

test "style precedence: on_style when checked=true" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const on_style = Style{ .fg = .green };
    const ts = ToggleSwitch.init("Test")
        .withChecked(true)
        .withOnStyle(on_style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    ts.render(&buf, area);

    // Knob at x=5 should have on_style
    const knob_cell = buf.getConst(5, 0);
    try testing.expect(knob_cell != null);
    try testing.expectEqual(on_style, knob_cell.?.style);
}

test "style precedence: disabled_style overrides on_style" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const on_style = Style{ .fg = .green };
    const disabled_style = Style{ .dim = true };
    const ts = ToggleSwitch.init("Test")
        .withChecked(true)
        .withOnStyle(on_style)
        .withDisabled(true)
        .withDisabledStyle(disabled_style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    ts.render(&buf, area);

    // Knob should have disabled_style, not on_style
    const knob_cell = buf.getConst(5, 0);
    try testing.expect(knob_cell != null);
    try testing.expectEqual(disabled_style, knob_cell.?.style);
}

test "style precedence: disabled_style overrides off_style" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const off_style = Style{ .fg = .gray };
    const disabled_style = Style{ .dim = true };
    const ts = ToggleSwitch.init("Test")
        .withChecked(false)
        .withOffStyle(off_style)
        .withDisabled(true)
        .withDisabledStyle(disabled_style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    ts.render(&buf, area);

    // Knob should have disabled_style
    const knob_cell = buf.getConst(1, 0);
    try testing.expect(knob_cell != null);
    try testing.expectEqual(disabled_style, knob_cell.?.style);
}

test "style precedence: focused_style overrides on_style when focused and not disabled" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const on_style = Style{ .fg = .green };
    const focused_style = Style{ .bold = true };
    const ts = ToggleSwitch.init("Test")
        .withChecked(true)
        .withOnStyle(on_style)
        .withFocus(true)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    ts.render(&buf, area);

    // Knob should have focused_style
    const knob_cell = buf.getConst(5, 0);
    try testing.expect(knob_cell != null);
    try testing.expectEqual(focused_style, knob_cell.?.style);
}

test "style precedence: focused_style ignored when disabled" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const on_style = Style{ .fg = .green };
    const disabled_style = Style{ .dim = true };
    const focused_style = Style{ .bold = true };
    const ts = ToggleSwitch.init("Test")
        .withChecked(true)
        .withOnStyle(on_style)
        .withDisabled(true)
        .withDisabledStyle(disabled_style)
        .withFocus(true)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    ts.render(&buf, area);

    // Knob should have disabled_style, not focused_style
    const knob_cell = buf.getConst(5, 0);
    try testing.expect(knob_cell != null);
    try testing.expectEqual(disabled_style, knob_cell.?.style);
}

// ============================================================================
// Group 7: ToggleSwitch Edge Cases
// ============================================================================

test "render with zero-width area does not panic" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const ts = ToggleSwitch.init("Test");
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    ts.render(&buf, area);
    // Should not panic; buffer should remain unchanged
    try testing.expect(true);
}

test "render with zero-height area does not panic" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const ts = ToggleSwitch.init("Test");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    ts.render(&buf, area);
    // Should not panic
    try testing.expect(true);
}

test "render with very narrow area (width < 7) does not panic" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const ts = ToggleSwitch.init("Test");
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };
    ts.render(&buf, area);
    // Should not panic; may render partial track or nothing
    try testing.expect(true);
}

test "render at offset position (x, y) respects area origin" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();

    const ts = ToggleSwitch.init("Test").withChecked(true);
    const area = Rect{ .x = 5, .y = 1, .width = 15, .height = 1 };
    ts.render(&buf, area);

    // Knob should be at absolute position (5+5, 1) = (10, 1)
    const knob_cell = buf.getConst(10, 1);
    try testing.expect(knob_cell != null);
    try testing.expectEqual('◉', knob_cell.?.char);
}

// ============================================================================
// Group 8: ToggleSwitchGroup focusedItem()
// ============================================================================

test "ToggleSwitchGroup.focusedItem returns pointer to currently focused item" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("First"),
        ToggleSwitch.init("Second"),
    };
    var group = ToggleSwitchGroup.init(&items);
    const focused = group.focusedItem();
    try testing.expect(focused != null);
    try testing.expectEqualStrings("First", focused.?.label);
}

test "ToggleSwitchGroup.focusedItem returns null when items empty" {
    var empty_items: [0]ToggleSwitch = undefined;
    var group = ToggleSwitchGroup.init(&empty_items);
    const focused = group.focusedItem();
    try testing.expectEqual(@as(?*ToggleSwitch, null), focused);
}

test "ToggleSwitchGroup.focusedItem changes with focus position" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
        ToggleSwitch.init("B"),
        ToggleSwitch.init("C"),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.focused = 1;
    const focused = group.focusedItem();
    try testing.expect(focused != null);
    try testing.expectEqualStrings("B", focused.?.label);
}

// ============================================================================
// Group 9: ToggleSwitchGroup focusNext() and focusPrev()
// ============================================================================

test "focusNext increments focus position" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
        ToggleSwitch.init("B"),
        ToggleSwitch.init("C"),
    };
    var group = ToggleSwitchGroup.init(&items);
    try testing.expectEqual(@as(usize, 0), group.focused);
    group.focusNext();
    try testing.expectEqual(@as(usize, 1), group.focused);
}

test "focusNext wraps around to start" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
        ToggleSwitch.init("B"),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.focused = 1;
    group.focusNext();
    try testing.expectEqual(@as(usize, 0), group.focused);
}

test "focusPrev decrements focus position" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
        ToggleSwitch.init("B"),
        ToggleSwitch.init("C"),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.focused = 2;
    group.focusPrev();
    try testing.expectEqual(@as(usize, 1), group.focused);
}

test "focusPrev wraps around to end" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
        ToggleSwitch.init("B"),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.focused = 0;
    group.focusPrev();
    try testing.expectEqual(@as(usize, 1), group.focused);
}

test "focusNext skips disabled items when possible" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A").withDisabled(false),
        ToggleSwitch.init("B").withDisabled(true),
        ToggleSwitch.init("C").withDisabled(false),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.focused = 0;
    group.focusNext();
    // Should skip B (disabled) and land on C (enabled)
    try testing.expectEqual(@as(usize, 2), group.focused);
}

test "focusPrev skips disabled items when possible" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A").withDisabled(false),
        ToggleSwitch.init("B").withDisabled(true),
        ToggleSwitch.init("C").withDisabled(false),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.focused = 2;
    group.focusPrev();
    // Should skip B (disabled) and land on A (enabled)
    try testing.expectEqual(@as(usize, 0), group.focused);
}

test "focusNext wraps when all items after are disabled" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A").withDisabled(false),
        ToggleSwitch.init("B").withDisabled(true),
        ToggleSwitch.init("C").withDisabled(true),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.focused = 0;
    group.focusNext();
    // Should wrap to A (the only enabled item)
    try testing.expectEqual(@as(usize, 0), group.focused);
}

test "focusNext on all-disabled items stays in place" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A").withDisabled(true),
        ToggleSwitch.init("B").withDisabled(true),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.focused = 0;
    group.focusNext();
    // All disabled, so stay at 0
    try testing.expectEqual(@as(usize, 0), group.focused);
}

test "focusPrev on all-disabled items stays in place" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A").withDisabled(true),
        ToggleSwitch.init("B").withDisabled(true),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.focused = 1;
    group.focusPrev();
    // All disabled, so stay at 1
    try testing.expectEqual(@as(usize, 1), group.focused);
}

test "focusNext does nothing on empty group" {
    var empty_items: [0]ToggleSwitch = undefined;
    var group = ToggleSwitchGroup.init(&empty_items);
    group.focusNext();
    // Should remain at 0 (or not change)
    try testing.expect(true);
}

// ============================================================================
// Group 10: ToggleSwitchGroup toggleFocused()
// ============================================================================

test "toggleFocused toggles checked state of focused item" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A").withChecked(false),
        ToggleSwitch.init("B").withChecked(true),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.toggleFocused();
    try testing.expect(items[0].checked);
    try testing.expect(!items[1].checked);
}

test "toggleFocused is no-op when focused item is disabled" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A").withChecked(false).withDisabled(true),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.toggleFocused();
    try testing.expect(!items[0].checked);
}

test "toggleFocused respects disable on different items" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A").withChecked(false).withDisabled(false),
        ToggleSwitch.init("B").withChecked(false).withDisabled(true),
    };
    var group = ToggleSwitchGroup.init(&items);
    group.focusNext();
    group.toggleFocused();
    // Focused on B (disabled), so toggle should be no-op
    try testing.expect(!items[1].checked);
}

// ============================================================================
// Group 11: ToggleSwitchGroup Rendering
// ============================================================================

test "ToggleSwitchGroup render lays out items vertically (one per row)" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("Item 1"),
        ToggleSwitch.init("Item 2"),
    };
    var group = ToggleSwitchGroup.init(&items);
    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    group.render(&buf, area);

    // First item at y=0, second at y=1
    const item1_track = buf.getConst(0, 0);
    const item2_track = buf.getConst(0, 1);
    try testing.expect(item1_track != null);
    try testing.expectEqual('[', item1_track.?.char);
    try testing.expect(item2_track != null);
    try testing.expectEqual('[', item2_track.?.char);
}

test "ToggleSwitchGroup render respects block border" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("Item"),
    };
    const block = (Block{}).withTitle("Options", .top_left);
    var group = ToggleSwitchGroup.init(&items).withBlock(block);
    var buf = try Buffer.init(testing.allocator, 30, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    group.render(&buf, area);

    // Block should render at (0,0) as top-left corner
    const corner = buf.getConst(0, 0);
    try testing.expect(corner != null);
    // Top-left should be a border character (not space, and not '0')
    try testing.expect(corner.?.char != ' ' and corner.?.char != '0');
}

test "ToggleSwitchGroup render applies base style to items" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("Item"),
    };
    const base_style = Style{ .fg = .blue };
    var group = ToggleSwitchGroup.init(&items).withStyle(base_style);
    var buf = try Buffer.init(testing.allocator, 30, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    group.render(&buf, area);

    // Item should have base_style applied
    const item_cell = buf.getConst(0, 0);
    try testing.expect(item_cell != null);
    // Style should include base_style or its components
    try testing.expect(true); // Placeholder; implementation will set style
}

test "ToggleSwitchGroup render focuses first item by default" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
        ToggleSwitch.init("B"),
    };
    var group = ToggleSwitchGroup.init(&items);
    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    group.render(&buf, area);

    // First item (y=0) should be marked as focused
    // Focused items typically get focused_style applied
    try testing.expect(true); // Placeholder; exact assertion depends on implementation
}

// ============================================================================
// Group 12: ToggleSwitchGroup Initialization
// ============================================================================

test "ToggleSwitchGroup.init sets default focused to 0" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
    };
    const group = ToggleSwitchGroup.init(&items);
    try testing.expectEqual(@as(usize, 0), group.focused);
}

test "ToggleSwitchGroup.init sets block to null by default" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
    };
    const group = ToggleSwitchGroup.init(&items);
    try testing.expectEqual(@as(?Block, null), group.block);
}

test "ToggleSwitchGroup.init sets style to empty Style by default" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
    };
    const group = ToggleSwitchGroup.init(&items);
    try testing.expectEqual(Style{}, group.style);
}

// ============================================================================
// Group 13: ToggleSwitchGroup Builder Methods Immutability
// ============================================================================

test "ToggleSwitchGroup.withBlock does not modify original" {
    var items = [_]ToggleSwitch{ ToggleSwitch.init("A") };
    const group1 = ToggleSwitchGroup.init(&items);
    const block = Block{};
    const group2 = group1.withBlock(block);
    try testing.expectEqual(@as(?Block, null), group1.block);
    try testing.expect(group2.block != null);
}

test "ToggleSwitchGroup.withStyle does not modify original" {
    var items = [_]ToggleSwitch{ ToggleSwitch.init("A") };
    const group1 = ToggleSwitchGroup.init(&items);
    const style = Style{ .fg = .red };
    const group2 = group1.withStyle(style);
    try testing.expectEqual(Style{}, group1.style);
    try testing.expectEqual(style, group2.style);
}

test "ToggleSwitchGroup.withHelp does not modify original" {
    var items = [_]ToggleSwitch{ ToggleSwitch.init("A") };
    const group1 = ToggleSwitchGroup.init(&items);
    const group2 = group1.withHelp(false);
    try testing.expect(group1.show_help);
    try testing.expect(!group2.show_help);
}
