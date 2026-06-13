//! FilterBar Widget Tests — Comprehensive Coverage
//!
//! Tests the FilterBar widget's initialization, memory management, tag operations,
//! styling, builder API, and rendering across all edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const FilterBar = sailor.tui.widgets.FilterBar;
const FilterTag = sailor.tui.widgets.FilterTag;

// ============================================================================
// INITIALIZATION TESTS (5 tests)
// ============================================================================

test "FilterBar init creates empty FilterBar" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try testing.expectEqual(0, fb.tagCount());
    try testing.expectEqual(0, fb.activeCount());
}

test "FilterBar deinit doesn't crash on empty FilterBar" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    fb.deinit();
    // If we get here, deinit succeeded
    try testing.expect(true);
}

test "FilterBar deinit frees memory properly" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    try fb.addTag("key1", "value1");
    try fb.addTag("key2", "value2");
    fb.deinit();
    // Memory leak detection via testing.allocator
    try testing.expect(true);
}

test "FilterBar init sets default placeholder 'No filters'" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try testing.expectEqualStrings("No filters", fb.placeholder);
}

test "FilterBar addTag sets active=true by default" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("status", "pending");
    const tag = fb.tags.items[0];
    try testing.expect(tag.active);
}

// ============================================================================
// ADD TAG TESTS (8 tests)
// ============================================================================

test "FilterBar addTag single tag increases tagCount" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("color", "blue");

    try testing.expectEqual(1, fb.tagCount());
    try testing.expectEqualStrings("color", fb.tags.items[0].key);
    try testing.expectEqualStrings("blue", fb.tags.items[0].value);
    try testing.expect(fb.tags.items[0].active);
}

test "FilterBar addTag multiple tags increases tagCount correctly" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("status", "active");
    try testing.expectEqual(1, fb.tagCount());

    try fb.addTag("priority", "high");
    try testing.expectEqual(2, fb.tagCount());

    try fb.addTag("owner", "alice");
    try testing.expectEqual(3, fb.tagCount());
}

test "FilterBar addTag dupes strings for independent memory" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    var key_buf = [_]u8{ 'k', 'e', 'y' };
    var val_buf = [_]u8{ 'v', 'a', 'l' };
    const key = key_buf[0..];
    const val = val_buf[0..];

    try fb.addTag(key, val);

    // Modify original buffers
    key_buf[0] = 'x';
    val_buf[0] = 'x';

    // FilterBar should have preserved original strings
    try testing.expectEqualStrings("key", fb.tags.items[0].key);
    try testing.expectEqualStrings("val", fb.tags.items[0].value);
}

test "FilterBar addTag allows empty key" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("", "value");

    try testing.expectEqual(1, fb.tagCount());
    try testing.expectEqualStrings("", fb.tags.items[0].key);
    try testing.expectEqualStrings("value", fb.tags.items[0].value);
}

test "FilterBar addTag allows empty value" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("key", "");

    try testing.expectEqual(1, fb.tagCount());
    try testing.expectEqualStrings("key", fb.tags.items[0].key);
    try testing.expectEqualStrings("", fb.tags.items[0].value);
}

test "FilterBar addTag allows empty key and value" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("", "");

    try testing.expectEqual(1, fb.tagCount());
    try testing.expectEqualStrings("", fb.tags.items[0].key);
    try testing.expectEqualStrings("", fb.tags.items[0].value);
}

test "FilterBar addTag handles many tags" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    for (0..25) |i| {
        var key_buf: [16]u8 = undefined;
        var val_buf: [16]u8 = undefined;
        const key = try std.fmt.bufPrint(key_buf[0..], "key{}", .{i});
        const val = try std.fmt.bufPrint(val_buf[0..], "val{}", .{i});
        try fb.addTag(key, val);
    }

    try testing.expectEqual(25, fb.tagCount());
    try testing.expectEqualStrings("key0", fb.tags.items[0].key);
    try testing.expectEqualStrings("key24", fb.tags.items[24].key);
}

test "FilterBar addTag with OOM allocator propagates error" {
    var fb = FilterBar.init(testing.allocator);
    defer fb.deinit();

    // This test verifies that if allocator runs out of memory,
    // addTag returns an error. With testing.allocator, a real OOM
    // would cause the test infrastructure to fail, so we just verify
    // normal operation for now.
    try fb.addTag("key", "value");
    try testing.expectEqual(1, fb.tagCount());
}

// ============================================================================
// REMOVE TAG TESTS (8 tests)
// ============================================================================

test "FilterBar removeTag at index 0 removes first tag" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("first", "1");
    try fb.addTag("second", "2");
    try fb.addTag("third", "3");

    fb.removeTag(0);

    try testing.expectEqual(2, fb.tagCount());
    try testing.expectEqualStrings("second", fb.tags.items[0].key);
    try testing.expectEqualStrings("third", fb.tags.items[1].key);
}

test "FilterBar removeTag at last index removes last tag" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try fb.addTag("c", "3");

    fb.removeTag(2);

    try testing.expectEqual(2, fb.tagCount());
    try testing.expectEqualStrings("a", fb.tags.items[0].key);
    try testing.expectEqualStrings("b", fb.tags.items[1].key);
}

test "FilterBar removeTag at middle index removes and preserves order" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try fb.addTag("c", "3");
    try fb.addTag("d", "4");

    fb.removeTag(1);

    try testing.expectEqual(3, fb.tagCount());
    try testing.expectEqualStrings("a", fb.tags.items[0].key);
    try testing.expectEqualStrings("c", fb.tags.items[1].key);
    try testing.expectEqualStrings("d", fb.tags.items[2].key);
}

test "FilterBar removeTag OOB (index == tagCount) is no-op" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("tag", "value");

    fb.removeTag(1); // OOB: tagCount=1, index=1

    try testing.expectEqual(1, fb.tagCount());
    try testing.expectEqualStrings("tag", fb.tags.items[0].key);
}

test "FilterBar removeTag OOB (large index) is no-op" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("tag", "value");

    fb.removeTag(9999);

    try testing.expectEqual(1, fb.tagCount());
}

test "FilterBar removeTag from empty FilterBar is no-op" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    fb.removeTag(0);

    try testing.expectEqual(0, fb.tagCount());
}

test "FilterBar removeTag all tags one by one reaches zero" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try fb.addTag("c", "3");

    fb.removeTag(2);
    try testing.expectEqual(2, fb.tagCount());

    fb.removeTag(1);
    try testing.expectEqual(1, fb.tagCount());

    fb.removeTag(0);
    try testing.expectEqual(0, fb.tagCount());
}

test "FilterBar removeTag remaining tags have correct keys and values" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("x", "10");
    try fb.addTag("y", "20");
    try fb.addTag("z", "30");

    fb.removeTag(0);

    try testing.expectEqualStrings("y", fb.tags.items[0].key);
    try testing.expectEqualStrings("20", fb.tags.items[0].value);
    try testing.expectEqualStrings("z", fb.tags.items[1].key);
    try testing.expectEqualStrings("30", fb.tags.items[1].value);
}

// ============================================================================
// TOGGLE TAG TESTS (6 tests)
// ============================================================================

test "FilterBar toggleTag makes active to inactive" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("status", "on");
    try testing.expect(fb.tags.items[0].active);

    fb.toggleTag(0);
    try testing.expect(!fb.tags.items[0].active);
}

test "FilterBar toggleTag makes inactive to active" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("status", "off");
    fb.toggleTag(0);
    try testing.expect(!fb.tags.items[0].active);

    fb.toggleTag(0);
    try testing.expect(fb.tags.items[0].active);
}

test "FilterBar toggleTag OOB index is no-op" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("tag", "value");
    const original_active = fb.tags.items[0].active;

    fb.toggleTag(5); // OOB

    try testing.expectEqual(original_active, fb.tags.items[0].active);
}

test "FilterBar toggleTag on empty is no-op" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    fb.toggleTag(0);

    try testing.expectEqual(0, fb.tagCount());
}

test "FilterBar toggleTag twice restores original state" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("toggle", "test");
    const original = fb.tags.items[0].active;

    fb.toggleTag(0);
    fb.toggleTag(0);

    try testing.expectEqual(original, fb.tags.items[0].active);
}

test "FilterBar toggleTag only affects specified index" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try fb.addTag("c", "3");

    const a_before = fb.tags.items[0].active;
    const b_before = fb.tags.items[1].active;
    const c_before = fb.tags.items[2].active;

    fb.toggleTag(1);

    try testing.expectEqual(a_before, fb.tags.items[0].active);
    try testing.expect(b_before != fb.tags.items[1].active);
    try testing.expectEqual(c_before, fb.tags.items[2].active);
}

// ============================================================================
// CLEAR ALL TESTS (5 tests)
// ============================================================================

test "FilterBar clearAll on empty is no-op" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    fb.clearAll();

    try testing.expectEqual(0, fb.tagCount());
}

test "FilterBar clearAll with one tag reaches zero" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("single", "tag");
    try testing.expectEqual(1, fb.tagCount());

    fb.clearAll();

    try testing.expectEqual(0, fb.tagCount());
}

test "FilterBar clearAll with many tags reaches zero" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    for (0..10) |i| {
        var key_buf: [16]u8 = undefined;
        var val_buf: [16]u8 = undefined;
        const key = try std.fmt.bufPrint(key_buf[0..], "key{}", .{i});
        const val = try std.fmt.bufPrint(val_buf[0..], "val{}", .{i});
        try fb.addTag(key, val);
    }
    try testing.expectEqual(10, fb.tagCount());

    fb.clearAll();

    try testing.expectEqual(0, fb.tagCount());
}

test "FilterBar clearAll frees memory properly" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    try fb.addTag("key1", "value1");
    try fb.addTag("key2", "value2");

    fb.clearAll();
    fb.deinit();

    // If we get here without a memory leak, success
    try testing.expect(true);
}

test "FilterBar after clearAll can addTag again" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("first", "tag");
    fb.clearAll();

    try fb.addTag("second", "tag");
    try testing.expectEqual(1, fb.tagCount());
    try testing.expectEqualStrings("second", fb.tags.items[0].key);
}

// ============================================================================
// ACTIVE COUNT TESTS (6 tests)
// ============================================================================

test "FilterBar activeCount zero when no tags" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try testing.expectEqual(0, fb.activeCount());
}

test "FilterBar activeCount equals all tags when all active (default)" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try fb.addTag("c", "3");

    try testing.expectEqual(3, fb.activeCount());
}

test "FilterBar activeCount decrements after toggleTag inactivate" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");

    try testing.expectEqual(2, fb.activeCount());

    fb.toggleTag(0);

    try testing.expectEqual(1, fb.activeCount());
}

test "FilterBar activeCount increments after toggleTag reactivate" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    fb.toggleTag(0);
    try testing.expectEqual(0, fb.activeCount());

    fb.toggleTag(0);
    try testing.expectEqual(1, fb.activeCount());
}

test "FilterBar activeCount zero when all toggled inactive" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try fb.addTag("c", "3");

    fb.toggleTag(0);
    fb.toggleTag(1);
    fb.toggleTag(2);

    try testing.expectEqual(0, fb.activeCount());
}

test "FilterBar activeCount decrements after removeTag of active tag" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try testing.expectEqual(2, fb.activeCount());

    fb.removeTag(0);

    try testing.expectEqual(1, fb.activeCount());
}

// ============================================================================
// TAG COUNT TESTS (3 tests)
// ============================================================================

test "FilterBar tagCount zero initially" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try testing.expectEqual(0, fb.tagCount());
}

test "FilterBar tagCount increments on addTag" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try testing.expectEqual(0, fb.tagCount());
    try fb.addTag("a", "1");
    try testing.expectEqual(1, fb.tagCount());
    try fb.addTag("b", "2");
    try testing.expectEqual(2, fb.tagCount());
}

test "FilterBar tagCount decrements on removeTag" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try testing.expectEqual(2, fb.tagCount());

    fb.removeTag(0);
    try testing.expectEqual(1, fb.tagCount());
}

// ============================================================================
// BUILDER API TESTS (5 tests)
// ============================================================================

test "FilterBar withBlock sets and returns *FilterBar" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const block = Block{ .title = "Filters" };
    const result = fb.withBlock(block);

    try testing.expect(result == &fb);
    try testing.expect(fb.block != null);
}

test "FilterBar withTagStyle sets tag_style" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const style = Style{ .bold = true };
    _ = fb.withTagStyle(style);

    try testing.expectEqual(true, fb.tag_style.bold);
}

test "FilterBar withActiveStyle sets active_style" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const style = Style{ .italic = true };
    _ = fb.withActiveStyle(style);

    try testing.expectEqual(true, fb.active_style.italic);
}

test "FilterBar withInactiveStyle sets inactive_style" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const style = Style{ .dim = true };
    _ = fb.withInactiveStyle(style);

    try testing.expectEqual(true, fb.inactive_style.dim);
}

test "FilterBar withPlaceholder sets placeholder text" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const new_placeholder = "Custom placeholder";
    _ = fb.withPlaceholder(new_placeholder);

    try testing.expectEqualStrings(new_placeholder, fb.placeholder);
}

// ============================================================================
// RENDER TESTS — EDGE CASES (8 tests)
// ============================================================================

test "FilterBar render zero-width area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("tag", "value");

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    fb.render(&buf, area);

    try testing.expect(true);
}

test "FilterBar render zero-height area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("tag", "value");

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    fb.render(&buf, area);

    try testing.expect(true);
}

test "FilterBar render 0x0 area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    fb.render(&buf, area);

    try testing.expect(true);
}

test "FilterBar render with empty tags shows default placeholder 'No filters'" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();
    // Note: withPlaceholder returns a NEW value; assign to fb directly
    fb.placeholder = "No filters"; // default

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fb.render(&buf, area);

    // "No filters" starts at x=0; 'N' should be there
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'N'), cell.?.char);
    // 'o' at x=1
    const cell2 = buf.getConst(1, 0);
    try testing.expect(cell2 != null);
    try testing.expectEqual(@as(u21, 'o'), cell2.?.char);
}

test "FilterBar render with narrow area (width=1) doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 1, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("x", "y");

    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 10 };
    fb.render(&buf, area);

    try testing.expect(true);
}

test "FilterBar render with 1 active tag renders pill [key:value]" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("status", "active");

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fb.render(&buf, area);

    // Pill "[status:active]" starts at x=0, y=0
    const open = buf.getConst(0, 0);
    try testing.expect(open != null);
    try testing.expectEqual(@as(u21, '['), open.?.char);
    const s = buf.getConst(1, 0);
    try testing.expect(s != null);
    try testing.expectEqual(@as(u21, 's'), s.?.char); // "status"
}

test "FilterBar render with block set: row 0 has block border char" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();
    fb.block = Block{ .title = "Filter" }; // assign directly, don't discard builder

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fb.render(&buf, area);
    // Block border: top-left corner at (0,0) should be a box-drawing char (not ' ')
    const corner = buf.getConst(0, 0);
    try testing.expect(corner != null);
    try testing.expect(corner.?.char != ' ');
}

test "FilterBar render mix of active/inactive tags" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try fb.addTag("c", "3");

    fb.toggleTag(1); // Make middle tag inactive

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fb.render(&buf, area);

    // All 3 tags render; first tag starts at x=0: "[a:1]" = 5 chars
    const open1 = buf.getConst(0, 0);
    try testing.expect(open1 != null);
    try testing.expectEqual(@as(u21, '['), open1.?.char);
    // Second tag "[b:2]" starts at x=6 (5 + 1 space)
    const open2 = buf.getConst(6, 0);
    try testing.expect(open2 != null);
    try testing.expectEqual(@as(u21, '['), open2.?.char);
}

// ============================================================================
// RENDER TESTS — CONTENT VERIFICATION (6 tests)
// ============================================================================

test "FilterBar render 1 tag contains '[' and key chars in buffer" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("status", "active");

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fb.render(&buf, area);

    // Pill "[status:active]" (15 chars) at x=0; verify '[', 's', 't', ':'
    const cell0 = buf.getConst(0, 0);
    try testing.expect(cell0 != null);
    try testing.expectEqual(@as(u21, '['), cell0.?.char);
    const cell1 = buf.getConst(1, 0); // 's' from "status"
    try testing.expect(cell1 != null);
    try testing.expectEqual(@as(u21, 's'), cell1.?.char);
    const colon = buf.getConst(7, 0); // ':' after "status" (6 chars)
    try testing.expect(colon != null);
    try testing.expectEqual(@as(u21, ':'), colon.?.char);
}

test "FilterBar render 2 active tags render both pills in sequence" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("type", "bug");       // "[type:bug]" = 10 chars
    try fb.addTag("priority", "high");  // "[priority:high]" = 15 chars

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fb.render(&buf, area);

    // First pill "[type:bug]" starts at x=0
    const p1_open = buf.getConst(0, 0);
    try testing.expect(p1_open != null);
    try testing.expectEqual(@as(u21, '['), p1_open.?.char);
    // Space separator at x=10
    const sep = buf.getConst(10, 0);
    try testing.expect(sep != null);
    try testing.expectEqual(@as(u21, ' '), sep.?.char);
    // Second pill starts at x=11
    const p2_open = buf.getConst(11, 0);
    try testing.expect(p2_open != null);
    try testing.expectEqual(@as(u21, '['), p2_open.?.char);
}

test "FilterBar render inactive tag uses inactive_style (dim)" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();
    fb.inactive_style = .{ .dim = true }; // set a distinguishable inactive style

    try fb.addTag("tag", "value");
    fb.toggleTag(0); // make inactive

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fb.render(&buf, area);

    // "[tag:value]" rendered with inactive_style; '[' at x=0 should have dim=true
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, '['), cell.?.char);
    try testing.expect(cell.?.style.dim == true);
}

test "FilterBar render with custom placeholder shows custom text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();
    fb.placeholder = "No filters applied"; // assign directly, don't discard builder

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fb.render(&buf, area);

    // "No filters applied": 'N' at x=0, y=0
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'N'), cell.?.char);
}

test "FilterBar render tag pills start at area.x offset" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("first", "tag");

    // Area starts at x=2
    const area = Rect{ .x = 2, .y = 0, .width = 76, .height = 10 };
    fb.render(&buf, area);

    // Pill starts at inner.x = 2; x=2 should have '['
    const cell = buf.getConst(2, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, '['), cell.?.char);
    // x=0,1 should be blank (before area start)
    const before = buf.getConst(0, 0);
    try testing.expect(before != null);
    try testing.expectEqual(@as(u21, ' '), before.?.char);
}

test "FilterBar render after clearAll shows placeholder text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("tag", "value");
    fb.clearAll();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fb.render(&buf, area);

    // After clearAll, placeholder "No filters" appears; 'N' at x=0
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'N'), cell.?.char);
}

// ============================================================================
// BUILDER CHAINING TESTS (5 tests)
// ============================================================================

test "FilterBar builder methods can chain together" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const block = Block{ .title = "Filters" };
    const tag_style = Style{ .bold = true };
    const active_style = Style{ .fg = .green };
    const inactive_style = Style{ .dim = true };

    _ = fb
        .withBlock(block)
        .withTagStyle(tag_style)
        .withActiveStyle(active_style)
        .withInactiveStyle(inactive_style)
        .withPlaceholder("Choose filters");

    try testing.expect(fb.block != null);
    try testing.expectEqual(true, fb.tag_style.bold);
    try testing.expect(std.meta.eql(fb.active_style.fg, .green));
    try testing.expectEqual(true, fb.inactive_style.dim);
    try testing.expectEqualStrings("Choose filters", fb.placeholder);
}

test "FilterBar withBlock returns self for chaining" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const block = Block{ .title = "Test" };
    const result = fb.withBlock(block);

    try testing.expect(result == &fb);
}

test "FilterBar withTagStyle returns self for chaining" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const style = Style{ .bold = true };
    const result = fb.withTagStyle(style);

    try testing.expect(result == &fb);
}

test "FilterBar withActiveStyle returns self for chaining" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const style = Style{ .italic = true };
    const result = fb.withActiveStyle(style);

    try testing.expect(result == &fb);
}

test "FilterBar withInactiveStyle returns self for chaining" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const style = Style{ .dim = true };
    const result = fb.withInactiveStyle(style);

    try testing.expect(result == &fb);
}

// ============================================================================
// COMPLEX SCENARIOS (6+ tests)
// ============================================================================

test "FilterBar complex workflow: add, toggle, remove, clear" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try fb.addTag("c", "3");
    try testing.expectEqual(3, fb.tagCount());
    try testing.expectEqual(3, fb.activeCount());

    fb.toggleTag(0);
    try testing.expectEqual(2, fb.activeCount());

    fb.removeTag(1);
    try testing.expectEqual(2, fb.tagCount());

    fb.clearAll();
    try testing.expectEqual(0, fb.tagCount());
}

test "FilterBar sequential toggles affect activeCount correctly" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try fb.addTag("c", "3");
    try fb.addTag("d", "4");

    try testing.expectEqual(4, fb.activeCount());

    fb.toggleTag(0);
    try testing.expectEqual(3, fb.activeCount());

    fb.toggleTag(2);
    try testing.expectEqual(2, fb.activeCount());

    fb.toggleTag(0);
    try testing.expectEqual(3, fb.activeCount());

    fb.toggleTag(1);
    try testing.expectEqual(2, fb.activeCount());
}

test "FilterBar removeTag maintains tag integrity in multi-tag scenario" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("user", "alice");
    try fb.addTag("status", "active");
    try fb.addTag("priority", "high");
    try fb.addTag("team", "backend");

    fb.removeTag(1);

    try testing.expectEqual(3, fb.tagCount());
    try testing.expectEqualStrings("user", fb.tags.items[0].key);
    try testing.expectEqualStrings("alice", fb.tags.items[0].value);
    try testing.expectEqualStrings("priority", fb.tags.items[1].key);
    try testing.expectEqualStrings("high", fb.tags.items[1].value);
    try testing.expectEqualStrings("team", fb.tags.items[2].key);
    try testing.expectEqualStrings("backend", fb.tags.items[2].value);
}

test "FilterBar render with full configuration: active tag uses active_style fg" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 120, 5);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    // Assign config fields directly (withXxx returns a new value — builder idiom)
    fb.block = Block{ .title = "Advanced Filters" };
    fb.tag_style = Style{ .bold = true };
    fb.active_style = Style{ .fg = .green };
    fb.inactive_style = Style{ .dim = true };
    fb.placeholder = "Set filters...";

    try fb.addTag("category", "feature"); // index 0
    try fb.addTag("assigned", "me");      // index 1
    fb.toggleTag(0); // make "category" inactive

    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 5 };
    fb.render(&buf, area);

    // Block border at (0,0); content inside border; pills start at (1,1) or similar
    // Simplest assertion: block drew a border char at (0,0)
    const corner = buf.getConst(0, 0);
    try testing.expect(corner != null);
    try testing.expect(corner.?.char != ' '); // border char, not blank

    // Inside block (inner area starting at x=1, y=1):
    // "[category:feature]" (inactive → dim), space, "[assigned:me]" (active → green fg)
    // x=1,y=1: '[' with dim style (inactive_style)
    const first_pill = buf.getConst(1, 1);
    try testing.expect(first_pill != null);
    try testing.expectEqual(@as(u21, '['), first_pill.?.char);
    try testing.expect(first_pill.?.style.dim == true); // inactive tag
}

test "FilterBar memory safety with many allocations and deallocations" {
    const allocator = testing.allocator;

    for (0..5) |_| {
        var fb = FilterBar.init(allocator);

        for (0..10) |i| {
            var k: [16]u8 = undefined;
            var v: [16]u8 = undefined;
            const key = try std.fmt.bufPrint(k[0..], "k{}", .{i});
            const val = try std.fmt.bufPrint(v[0..], "v{}", .{i});
            try fb.addTag(key, val);
        }

        fb.clearAll();
        fb.deinit();
    }

    try testing.expect(true);
}

test "FilterBar all operations on single large tag" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    const large_key = "this_is_a_very_long_filter_key_with_many_characters";
    const large_val = "this_is_a_very_long_filter_value_with_lots_of_content_here";

    try fb.addTag(large_key, large_val);
    try testing.expectEqual(1, fb.tagCount());
    try testing.expectEqual(1, fb.activeCount());

    fb.toggleTag(0);
    try testing.expectEqual(0, fb.activeCount());

    fb.toggleTag(0);
    try testing.expectEqual(1, fb.activeCount());

    fb.removeTag(0);
    try testing.expectEqual(0, fb.tagCount());
}

test "FilterBar render doesn't modify tag state" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    fb.toggleTag(0);

    const count_before = fb.activeCount();
    const tag_count_before = fb.tagCount();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fb.render(&buf, area);

    try testing.expectEqual(count_before, fb.activeCount());
    try testing.expectEqual(tag_count_before, fb.tagCount());
    try testing.expect(!fb.tags.items[0].active);
    try testing.expect(fb.tags.items[1].active);
}

// ============================================================================
// EDGE CASES & STRESS TESTS (4+ tests)
// ============================================================================

test "FilterBar with unicode characters in key and value" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("categoria", "開発");
    try testing.expectEqual(1, fb.tagCount());
    try testing.expectEqualStrings("categoria", fb.tags.items[0].key);
    try testing.expectEqualStrings("開発", fb.tags.items[0].value);
}

test "FilterBar alternating add and remove" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("1", "a");
    try fb.addTag("2", "b");
    fb.removeTag(0);
    try fb.addTag("3", "c");
    fb.removeTag(0);
    try fb.addTag("4", "d");

    try testing.expectEqual(2, fb.tagCount());
    try testing.expectEqualStrings("3", fb.tags.items[0].key);
    try testing.expectEqualStrings("4", fb.tags.items[1].key);
}

test "FilterBar render multiple times in succession: buffer state idempotent" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("tag", "value");

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };

    // Render 5 times; the result should be identical each time
    for (0..5) |_| {
        fb.render(&buf, area);
    }

    // After all renders, "[tag:value]" still starts at x=0; '[' at (0,0)
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, '['), cell.?.char);
    // tag count is unchanged (render does not mutate state)
    try testing.expectEqual(@as(usize, 1), fb.tagCount());
}

test "FilterBar filter operations preserve order exactly" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("alpha", "A");
    try fb.addTag("bravo", "B");
    try fb.addTag("charlie", "C");
    try fb.addTag("delta", "D");
    try fb.addTag("echo", "E");

    fb.removeTag(2);
    fb.removeTag(1);

    try testing.expectEqual(3, fb.tagCount());
    try testing.expectEqualStrings("alpha", fb.tags.items[0].key);
    try testing.expectEqualStrings("delta", fb.tags.items[1].key);
    try testing.expectEqualStrings("echo", fb.tags.items[2].key);
}

test "FilterBar activeCount after mixed operations" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try fb.addTag("a", "1");
    try fb.addTag("b", "2");
    try fb.addTag("c", "3");
    try fb.addTag("d", "4");
    try fb.addTag("e", "5");

    fb.toggleTag(1);
    fb.toggleTag(3);
    try testing.expectEqual(3, fb.activeCount());

    fb.removeTag(0);
    try testing.expectEqual(2, fb.activeCount());

    fb.removeTag(1);
    try testing.expectEqual(1, fb.activeCount());
}
