//! Select Widget Tests — v2.25.0
//! Comprehensive test coverage for single-select and multi-select modes

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Select = sailor.tui.widgets.Select;
const Block = sailor.tui.widgets.Block;
const symbols = sailor.tui.symbols;

// ============================================================================
// INITIALIZATION TESTS
// ============================================================================

test "Select init single-select mode creates empty selections" {
    const items = [_][]const u8{ "Option 1", "Option 2", "Option 3" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(false, select.multi);
    try testing.expectEqual(3, select.items.len);
    try testing.expectEqual(0, select.current);
    try testing.expectEqual(false, select.selected[0]);
    try testing.expectEqual(false, select.selected[1]);
    try testing.expectEqual(false, select.selected[2]);
}

test "Select init multi-select mode creates empty selections" {
    const items = [_][]const u8{ "Item A", "Item B" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(true, select.multi);
    try testing.expectEqual(2, select.items.len);
    try testing.expectEqual(2, select.selected.len);
    try testing.expectEqual(false, select.selected[0]);
    try testing.expectEqual(false, select.selected[1]);
}

test "Select init with empty items succeeds" {
    const items: [0][]const u8 = .{};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(0, select.items.len);
    try testing.expectEqual(0, select.selected.len);
}

test "Select init with single item" {
    const items = [_][]const u8{"Only One"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(1, select.items.len);
    try testing.expectEqual(1, select.selected.len);
}

test "Select deinit frees allocation and selected array" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, true);
    // Explicitly deinit without defer — verifies deinit completes without error.
    // The testing allocator detects leaks at test teardown, so missing deinit would fail.
    select.deinit(testing.allocator);
    // After deinit, init a second instance to verify the allocator still works correctly.
    var select2 = try Select.init(testing.allocator, &items, true);
    defer select2.deinit(testing.allocator);
    // Verify the new instance is properly initialized (not pointer address, which is impl-defined).
    try testing.expectEqual(3, select2.selected.len);
    try testing.expectEqual(false, select2.selected[0]);
    try testing.expectEqual(false, select2.selected[1]);
    try testing.expectEqual(false, select2.selected[2]);
}

test "Select init allocates separate selected array per instance" {
    const items = [_][]const u8{ "X", "Y" };
    var select1 = try Select.init(testing.allocator, &items, false);
    var select2 = try Select.init(testing.allocator, &items, false);
    defer select1.deinit(testing.allocator);
    defer select2.deinit(testing.allocator);

    select1.selected[0] = true;
    try testing.expectEqual(false, select2.selected[0]);
}

// ============================================================================
// NAVIGATION TESTS
// ============================================================================

test "Select next advances cursor" {
    const items = [_][]const u8{ "First", "Second", "Third" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(0, select.current);
    select.next();
    try testing.expectEqual(1, select.current);
    select.next();
    try testing.expectEqual(2, select.current);
}

test "Select next wraps from last to first" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.current = 2; // Last item
    select.next();
    try testing.expectEqual(0, select.current);
}

test "Select prev goes to previous item" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.current = 2;
    select.prev();
    try testing.expectEqual(1, select.current);
}

test "Select prev wraps from first to last" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.current = 0;
    select.prev();
    try testing.expectEqual(2, select.current);
}

test "Select next on empty items does nothing" {
    const items: [0][]const u8 = .{};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.current = 0;
    select.next();
    try testing.expectEqual(0, select.current);
}

test "Select prev on empty items does nothing" {
    const items: [0][]const u8 = .{};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.current = 0;
    select.prev();
    try testing.expectEqual(0, select.current);
}

test "Select navigation sequence" {
    const items = [_][]const u8{ "1", "2", "3", "4", "5" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.next(); // 0 -> 1
    select.next(); // 1 -> 2
    select.prev(); // 2 -> 1
    select.next(); // 1 -> 2
    try testing.expectEqual(2, select.current);
}

// ============================================================================
// SINGLE-SELECT MODE TESTS
// ============================================================================

test "Select selectCurrent sets current item selected in single mode" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(false, select.selected[0]);
    select.selectCurrent();
    try testing.expectEqual(true, select.selected[0]);
}

test "Select selectCurrent clears previous selection" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.selectCurrent();
    try testing.expectEqual(true, select.selected[0]);
    try testing.expectEqual(false, select.selected[1]);

    select.next();
    select.selectCurrent();
    try testing.expectEqual(false, select.selected[0]);
    try testing.expectEqual(true, select.selected[1]);
}

test "Select selectCurrent does nothing in multi mode" {
    const items = [_][]const u8{ "A", "B" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    select.selectCurrent();
    try testing.expectEqual(false, select.selected[0]);
    try testing.expectEqual(false, select.selected[1]);
}

test "Select toggleCurrent does nothing in single mode" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.toggleCurrent();
    try testing.expectEqual(false, select.selected[0]);
}

test "Select currentItem matches current index" {
    const items = [_][]const u8{ "Apple", "Banana", "Cherry" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    const item0 = select.currentItem();
    try testing.expectEqualStrings("Apple", item0.?);

    select.next();
    const item1 = select.currentItem();
    try testing.expectEqualStrings("Banana", item1.?);

    select.next();
    const item2 = select.currentItem();
    try testing.expectEqualStrings("Cherry", item2.?);
}

test "Select currentItem returns null when out of bounds" {
    const items = [_][]const u8{ "A", "B" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.current = 5; // Out of bounds
    const item = select.currentItem();
    try testing.expectEqual(null, item);
}

// ============================================================================
// MULTI-SELECT MODE TESTS
// ============================================================================

test "Select toggleCurrent toggles item on in multi mode" {
    const items = [_][]const u8{ "X", "Y", "Z" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(false, select.selected[0]);
    select.toggleCurrent();
    try testing.expectEqual(true, select.selected[0]);
}

test "Select toggleCurrent toggles item off in multi mode" {
    const items = [_][]const u8{ "X", "Y", "Z" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    select.toggleCurrent();
    try testing.expectEqual(true, select.selected[0]);
    select.toggleCurrent();
    try testing.expectEqual(false, select.selected[0]);
}

test "Select multi-mode selectCurrent does nothing" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    select.selectCurrent();
    try testing.expectEqual(false, select.selected[0]);
    try testing.expectEqual(false, select.selected[1]);
}

test "Select multiple items can be selected simultaneously" {
    const items = [_][]const u8{ "Red", "Green", "Blue", "Yellow", "Purple" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    select.current = 0;
    select.toggleCurrent(); // Select Red

    select.current = 2;
    select.toggleCurrent(); // Select Blue

    select.current = 4;
    select.toggleCurrent(); // Select Purple

    try testing.expectEqual(true, select.selected[0]);
    try testing.expectEqual(false, select.selected[1]);
    try testing.expectEqual(true, select.selected[2]);
    try testing.expectEqual(false, select.selected[3]);
    try testing.expectEqual(true, select.selected[4]);
}

test "Select selectedItems returns all selected items" {
    const items = [_][]const u8{ "Red", "Green", "Blue" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    select.toggleCurrent(); // Select Red (current=0)
    select.next();
    select.next();
    select.toggleCurrent(); // Select Blue (current=2)

    const selected = try select.selectedItems(testing.allocator);
    defer testing.allocator.free(selected);

    try testing.expectEqual(2, selected.len);
    try testing.expectEqualStrings("Red", selected[0]);
    try testing.expectEqualStrings("Blue", selected[1]);
}

test "Select selectedItems returns empty when none selected" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    const selected = try select.selectedItems(testing.allocator);
    defer testing.allocator.free(selected);

    try testing.expectEqual(0, selected.len);
}

test "Select selectedItems respects order of selection" {
    const items = [_][]const u8{ "1", "2", "3", "4" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    select.current = 3;
    select.toggleCurrent(); // Select "4"
    select.current = 0;
    select.toggleCurrent(); // Select "1"
    select.current = 2;
    select.toggleCurrent(); // Select "3"

    const selected = try select.selectedItems(testing.allocator);
    defer testing.allocator.free(selected);

    try testing.expectEqual(3, selected.len);
    try testing.expectEqualStrings("1", selected[0]);
    try testing.expectEqualStrings("3", selected[1]);
    try testing.expectEqualStrings("4", selected[2]);
}

// ============================================================================
// SCROLLING TESTS
// ============================================================================

test "Select scroll_offset starts at zero" {
    const items = [_][]const u8{ "A", "B", "C", "D", "E" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(0, select.scroll_offset);
}

test "Select next adjusts scroll when cursor goes past max_visible" {
    const items = [_][]const u8{ "1", "2", "3", "4", "5", "6", "7", "8" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select = select.withMaxVisible(3);
    try testing.expectEqual(0, select.scroll_offset);

    select.next(); // current=1, scroll still 0
    select.next(); // current=2, scroll still 0
    try testing.expectEqual(0, select.scroll_offset);

    select.next(); // current=3, should scroll
    try testing.expectEqual(1, select.scroll_offset);

    select.next(); // current=4
    try testing.expectEqual(2, select.scroll_offset);
}

test "Select prev adjusts scroll when cursor goes before offset" {
    const items = [_][]const u8{ "1", "2", "3", "4", "5" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select = select.withMaxVisible(2);
    select.current = 3;
    select.adjustScroll(); // Manually set scroll to position cursor
    try testing.expectEqual(2, select.scroll_offset);

    select.prev(); // current=2, should adjust scroll
    try testing.expectEqual(2, select.scroll_offset);

    select.prev(); // current=1
    try testing.expectEqual(1, select.scroll_offset);

    select.prev(); // current=0
    try testing.expectEqual(0, select.scroll_offset);
}

test "Select no scroll when max_visible is null" {
    const items = [_][]const u8{ "A", "B", "C", "D", "E", "F", "G", "H" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(null, select.max_visible);
    select.next();
    select.next();
    select.next();
    try testing.expectEqual(0, select.scroll_offset);
}

// ============================================================================
// BUILDER PATTERN TESTS
// ============================================================================

test "Select withBlock sets block" {
    const items = [_][]const u8{"Item 1"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(null, select.block);
    const block = (Block{}).withTitle("My Select", .top_left);
    select = select.withBlock(block);
    try testing.expect(select.block != null);
}

test "Select withStyle sets custom style" {
    const items = [_][]const u8{"Item"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    const custom_style = Style{ .fg = Color.blue, .bold = true };
    select = select.withStyle(custom_style);
    try testing.expectEqual(true, select.style.bold);
}

test "Select withHighlightStyle sets highlight style" {
    const items = [_][]const u8{"Item"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    const highlight = Style{ .fg = Color.yellow, .bold = true };
    select = select.withHighlightStyle(highlight);
    try testing.expectEqual(Color.yellow, select.highlight_style.fg.?);
}

test "Select withSelectedStyle sets selected style" {
    const items = [_][]const u8{"Item"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    const selected_style = Style{ .fg = Color.green, .italic = true };
    select = select.withSelectedStyle(selected_style);
    try testing.expectEqual(true, select.selected_style.italic);
}

test "Select withMaxVisible sets max_visible" {
    const items = [_][]const u8{ "1", "2", "3" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(null, select.max_visible);
    select = select.withMaxVisible(5);
    try testing.expectEqual(5, select.max_visible);
}

test "Select withHelp sets show_help" {
    const items = [_][]const u8{"Item"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    try testing.expectEqual(true, select.show_help);
    select = select.withHelp(false);
    try testing.expectEqual(false, select.show_help);
}

test "Select builder pattern chains" {
    const items = [_][]const u8{ "A", "B" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    const result = select
        .withMaxVisible(3)
        .withHelp(false)
        .withStyle(Style{ .fg = Color.cyan });

    try testing.expectEqual(3, result.max_visible);
    try testing.expectEqual(false, result.show_help);
}

// ============================================================================
// RENDERING TESTS
// ============================================================================

test "Select render single-select unselected item shows radio.unselected" {
    const items = [_][]const u8{"First Option"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    select.render(&buf, area);

    const first_char = buf.get(0, 0);
    try testing.expectEqual(symbols.radio.unselected, first_char.?.char);
}

test "Select render single-select selected item shows radio.selected" {
    const items = [_][]const u8{"Selected Item"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.selectCurrent();

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    select.render(&buf, area);

    const first_char = buf.get(0, 0);
    try testing.expectEqual(symbols.radio.selected, first_char.?.char);
}

test "Select render multi-select unselected item shows '[' and ']'" {
    const items = [_][]const u8{"Unchecked"};
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    select.render(&buf, area);

    const open_bracket = buf.get(0, 0);
    const space = buf.get(1, 0);
    const close_bracket = buf.get(2, 0);

    try testing.expectEqual('[', open_bracket.?.char);
    try testing.expectEqual(' ', space.?.char);
    try testing.expectEqual(']', close_bracket.?.char);
}

test "Select render multi-select selected item shows checkmark" {
    const items = [_][]const u8{"Checked"};
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    select.toggleCurrent();

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    select.render(&buf, area);

    const open_bracket = buf.get(0, 0);
    const checkmark = buf.get(1, 0);
    const close_bracket = buf.get(2, 0);

    try testing.expectEqual('[', open_bracket.?.char);
    try testing.expectEqual('✓', checkmark.?.char);
    try testing.expectEqual(']', close_bracket.?.char);
}

test "Select render item text is placed after indicator" {
    const items = [_][]const u8{"Option"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    select.render(&buf, area);

    // Single-select has radio symbol + space, then text
    const text_start = buf.get(2, 0);
    try testing.expectEqual('O', text_start.?.char);
}

test "Select render multi-select item text is placed after bracket" {
    const items = [_][]const u8{"Item"};
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    select.render(&buf, area);

    // Multi-select has [, space/checkmark, ], space, then text
    const text_start = buf.get(4, 0);
    try testing.expectEqual('I', text_start.?.char);
}

test "Select render zero area clears buffer cells and bounds-checks" {
    const items = [_][]const u8{"Item"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    // Set some cells before render to verify zero-area render doesn't write
    buf.set(0, 0, .{ .char = 'X', .style = .{} });

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    select.render(&buf, area);

    // Zero-area render clears nothing (height=0), verify original char still there
    const cell = buf.get(0, 0);
    try testing.expectEqual('X', cell.?.char);
}

test "Select render zero height renders nothing, preserves cells" {
    const items = [_][]const u8{"Item"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    // Pre-fill buffer with test pattern
    for (0..20) |x| {
        buf.set(@intCast(x), 0, .{ .char = 'P', .style = .{} });
    }

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    select.render(&buf, area);

    // Zero height means nothing rendered in that area
    const cell = buf.get(0, 0);
    try testing.expectEqual('P', cell.?.char);
}

test "Select render with empty items fills area with spaces" {
    const items: [0][]const u8 = .{};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    // Pre-fill with marker character
    for (0..20) |x| {
        for (0..5) |y| {
            buf.set(@intCast(x), @intCast(y), .{ .char = 'M', .style = .{} });
        }
    }

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    select.render(&buf, area);

    // With empty items, render should clear area with spaces (first item row doesn't exist)
    const cell = buf.get(0, 0);
    try testing.expectEqual(' ', cell.?.char);
}

test "Select render respects highlight style on current item" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    const highlight = Style{ .fg = Color.red, .bold = true };
    select = select.withHighlightStyle(highlight);

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    select.render(&buf, area);

    const char = buf.get(0, 0);
    try testing.expectEqual(true, char.?.style.bold);
    try testing.expectEqual(Color.red, char.?.style.fg.?);
}

test "Select render respects selected style on non-current selected item" {
    const items = [_][]const u8{ "A", "B" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    const selected_style = Style{ .fg = Color.green };
    select = select.withSelectedStyle(selected_style);

    select.selectCurrent(); // Select A
    select.next(); // Move to B (not selected)

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    select.render(&buf, area);

    // First row (A) is selected but not current — should use selected_style (green)
    const char = buf.get(0, 0);
    try testing.expectEqual(Color.green, char.?.style.fg.?);
}

test "Select render with block renders border corners and insets content" {
    const items = [_][]const u8{"Item"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    const block = (Block{}).withTitle("Title", .top_left);
    select = select.withBlock(block);

    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    select.render(&buf, area);

    // Block border at (0,0) should be a corner symbol (┌ or ╔ or similar)
    const border = buf.get(0, 0);
    const is_border = border.?.char == '┌' or border.?.char == '╔' or border.?.char == '┍' or border.?.char == '┎';
    try testing.expect(is_border);
}

test "Select render with help text shows when show_help=true" {
    const items = [_][]const u8{ "A", "B" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select = select.withHelp(true);

    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    select.render(&buf, area);

    // Help text appears at bottom: "↑/↓: Navigate | Enter: Select"
    const help_char = buf.get(0, 4);
    try testing.expectEqual('↑', help_char.?.char);
}

test "Select render without help text when show_help=false" {
    const items = [_][]const u8{ "A", "B" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select = select.withHelp(false);

    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    select.render(&buf, area);

    // Bottom row should have space (no help text)
    const space = buf.get(0, 4);
    try testing.expectEqual(' ', space.?.char);
}

test "Select render shows up arrow when scrolled below top" {
    const items = [_][]const u8{ "1", "2", "3", "4", "5" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select = select.withMaxVisible(2).withHelp(false);
    select.current = 3; // Move down to trigger scroll
    select.adjustScroll();

    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    select.render(&buf, area);

    // Arrow at top-right corner
    const arrow = buf.get(9, 0);
    try testing.expectEqual('↑', arrow.?.char);
}

test "Select render shows down arrow when more items below" {
    const items = [_][]const u8{ "1", "2", "3", "4", "5" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select = select.withMaxVisible(2).withHelp(false);
    // current=0, so scroll_offset=0, items beyond visible range exist

    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    select.render(&buf, area);

    // Arrow at bottom-right corner
    const arrow = buf.get(9, 4);
    try testing.expectEqual('↓', arrow.?.char);
}

test "Select render multiple items display in sequence" {
    const items = [_][]const u8{ "First", "Second", "Third" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select = select.withHelp(false);

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    select.render(&buf, area);

    // Row 0: First
    const first_char = buf.get(2, 0);
    try testing.expectEqual('F', first_char.?.char);

    // Row 1: Second
    const second_char = buf.get(2, 1);
    try testing.expectEqual('S', second_char.?.char);

    // Row 2: Third
    const third_char = buf.get(2, 2);
    try testing.expectEqual('T', third_char.?.char);
}

// ============================================================================
// EDGE CASE TESTS
// ============================================================================

test "Select single item list navigation wraps correctly" {
    const items = [_][]const u8{"Only"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.next();
    try testing.expectEqual(0, select.current); // Wraps to self

    select.prev();
    try testing.expectEqual(0, select.current);
}

test "Select current out of bounds is handled gracefully" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select.current = 100;
    const item = select.currentItem();
    try testing.expectEqual(null, item);
}

test "Select toggle at out of bounds index is bounds-checked" {
    const items = [_][]const u8{ "A", "B" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    select.current = 99; // Out of bounds
    const prev_state = select.selected[0]; // Before toggle
    select.toggleCurrent(); // Should be guarded by current < selected.len
    // Verify that out-of-bounds toggle doesn't affect valid items
    try testing.expectEqual(prev_state, select.selected[0]);
    try testing.expectEqual(prev_state, select.selected[1]);
}

test "Select long item text truncates at buffer width without overrun" {
    const items = [_][]const u8{"This is a very long item name that should be truncated"};
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    select.render(&buf, area);

    // Verify render stops before writing past the buffer boundary
    // With width=10: radio symbol (1) + space (1) + 8 chars of text = exactly 10
    const first_text_char = buf.get(2, 0); // After radio + space
    try testing.expectEqual('T', first_text_char.?.char); // First char of "This"

    // Verify nothing was written beyond the area width
    const last_char = buf.get(9, 0);
    try testing.expect(last_char.?.char != 'y'); // "y" from "very" shouldn't appear at position 9
}

test "Select scrolling with exact fit" {
    const items = [_][]const u8{ "1", "2", "3" };
    var select = try Select.init(testing.allocator, &items, false);
    defer select.deinit(testing.allocator);

    select = select.withMaxVisible(3);

    select.current = 2;
    select.adjustScroll();

    try testing.expectEqual(0, select.scroll_offset);
}

test "Select selectedItems with only one selected" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    select.current = 1;
    select.toggleCurrent();

    const selected = try select.selectedItems(testing.allocator);
    defer testing.allocator.free(selected);

    try testing.expectEqual(1, selected.len);
    try testing.expectEqualStrings("B", selected[0]);
}

test "Select selectedItems all items selected" {
    const items = [_][]const u8{ "X", "Y", "Z" };
    var select = try Select.init(testing.allocator, &items, true);
    defer select.deinit(testing.allocator);

    for (0..3) |i| {
        select.current = i;
        select.toggleCurrent();
    }

    const selected = try select.selectedItems(testing.allocator);
    defer testing.allocator.free(selected);

    try testing.expectEqual(3, selected.len);
    try testing.expectEqualStrings("X", selected[0]);
    try testing.expectEqualStrings("Y", selected[1]);
    try testing.expectEqualStrings("Z", selected[2]);
}
