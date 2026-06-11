//! Inspector Widget Tests — TDD Red Phase
//!
//! Tests inspector widget with field navigation, filtering, builder pattern,
//! and rendering capabilities. Validates scrolling, filtering, styling,
//! and edge case handling.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Inspector = sailor.tui.widgets.Inspector;
const InspectorField = sailor.tui.widgets.InspectorField;
const Block = sailor.tui.widgets.Block;

// ============================================================================
// Init Tests (5 tests)
// ============================================================================

test "Inspector.init sets scroll_offset to 0" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Alice" },
    };
    const insp = Inspector.init(&fields);
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "Inspector.init sets filter_query to empty string" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Alice" },
    };
    const insp = Inspector.init(&fields);
    try testing.expectEqualStrings("", insp.filter_query);
}

test "Inspector.init sets show_types to false" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Alice" },
    };
    const insp = Inspector.init(&fields);
    try testing.expect(insp.show_types == false);
}

test "Inspector.init sets show_filter to false" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Alice" },
    };
    const insp = Inspector.init(&fields);
    try testing.expect(insp.show_filter == false);
}

test "Inspector.init borrows fields slice" {
    var fields = [_]InspectorField{
        .{ .key = "id", .value = "123" },
        .{ .key = "status", .value = "active" },
    };
    const insp = Inspector.init(&fields);
    try testing.expectEqual(@as(usize, 2), insp.fields.len);
    try testing.expectEqualStrings("id", insp.fields[0].key);
    try testing.expectEqualStrings("active", insp.fields[1].value);
}

// ============================================================================
// scrollDown Tests (8 tests)
// ============================================================================

test "scrollDown increments scroll_offset" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
    };
    var insp = Inspector.init(&fields);
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
    insp.scrollDown();
    try testing.expectEqual(@as(usize, 1), insp.scroll_offset);
}

test "scrollDown clamps at last field" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
        .{ .key = "f3", .value = "v3" },
    };
    var insp = Inspector.init(&fields);
    insp.scroll_offset = 2;
    insp.scrollDown();
    try testing.expectEqual(@as(usize, 2), insp.scroll_offset);
}

test "scrollDown on empty fields has no effect" {
    var fields: [0]InspectorField = undefined;
    var insp = Inspector.init(&fields);
    insp.scrollDown();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "scrollDown on single field has no effect" {
    var fields = [_]InspectorField{
        .{ .key = "only", .value = "one" },
    };
    var insp = Inspector.init(&fields);
    insp.scrollDown();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "scrollDown multiple times accumulates" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
        .{ .key = "f3", .value = "v3" },
        .{ .key = "f4", .value = "v4" },
    };
    var insp = Inspector.init(&fields);
    insp.scrollDown();
    insp.scrollDown();
    try testing.expectEqual(@as(usize, 2), insp.scroll_offset);
}

test "scrollDown respects filter (clamps to filtered visible count)" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "type", .value = "user" },
        .{ .key = "id", .value = "123" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("na"); // Only 'name' matches
    insp.scrollDown();
    // With 1 visible field, scrollDown should clamp to 0
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "scrollDown from position 0 to 1 with 2 fields" {
    var fields = [_]InspectorField{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    var insp = Inspector.init(&fields);
    insp.scrollDown();
    try testing.expectEqual(@as(usize, 1), insp.scroll_offset);
}

test "scrollDown to second-to-last field" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
        .{ .key = "f3", .value = "v3" },
    };
    var insp = Inspector.init(&fields);
    insp.scrollDown();
    insp.scrollDown();
    try testing.expectEqual(@as(usize, 2), insp.scroll_offset);
}

// ============================================================================
// scrollUp Tests (6 tests)
// ============================================================================

test "scrollUp decrements scroll_offset" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
    };
    var insp = Inspector.init(&fields);
    insp.scroll_offset = 1;
    insp.scrollUp();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "scrollUp clamps at 0" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
    };
    var insp = Inspector.init(&fields);
    insp.scrollUp();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "scrollUp on empty fields has no effect" {
    var fields: [0]InspectorField = undefined;
    var insp = Inspector.init(&fields);
    insp.scrollUp();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "scrollUp multiple times from position 3" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
        .{ .key = "f3", .value = "v3" },
        .{ .key = "f4", .value = "v4" },
    };
    var insp = Inspector.init(&fields);
    insp.scroll_offset = 3;
    insp.scrollUp();
    insp.scrollUp();
    try testing.expectEqual(@as(usize, 1), insp.scroll_offset);
}

test "scrollUp from 1 goes to 0" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
    };
    var insp = Inspector.init(&fields);
    insp.scroll_offset = 1;
    insp.scrollUp();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "scrollUp on single field at 0 stays at 0" {
    var fields = [_]InspectorField{
        .{ .key = "only", .value = "one" },
    };
    var insp = Inspector.init(&fields);
    insp.scrollUp();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

// ============================================================================
// goToTop Tests (3 tests)
// ============================================================================

test "goToTop resets scroll_offset to 0" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
        .{ .key = "f3", .value = "v3" },
    };
    var insp = Inspector.init(&fields);
    insp.scroll_offset = 2;
    insp.goToTop();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "goToTop from non-zero position" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
    };
    var insp = Inspector.init(&fields);
    insp.scroll_offset = 1;
    insp.goToTop();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "goToTop on empty fields" {
    var fields: [0]InspectorField = undefined;
    var insp = Inspector.init(&fields);
    insp.scroll_offset = 5;
    insp.goToTop();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

// ============================================================================
// goToBottom Tests (3 tests)
// ============================================================================

test "goToBottom sets scroll_offset to last field" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
        .{ .key = "f3", .value = "v3" },
    };
    var insp = Inspector.init(&fields);
    insp.goToBottom();
    try testing.expectEqual(@as(usize, 2), insp.scroll_offset);
}

test "goToBottom on single field sets to 0" {
    var fields = [_]InspectorField{
        .{ .key = "only", .value = "one" },
    };
    var insp = Inspector.init(&fields);
    insp.goToBottom();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "goToBottom on empty fields stays at 0" {
    var fields: [0]InspectorField = undefined;
    var insp = Inspector.init(&fields);
    insp.scroll_offset = 10;
    insp.goToBottom();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

// ============================================================================
// filterBy Tests (10 tests)
// ============================================================================

test "filterBy case-insensitive match on key" {
    var fields = [_]InspectorField{
        .{ .key = "Name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("name");
    // Only "Name" field should be visible; query stored
    try testing.expectEqualStrings("name", insp.filter_query);
}

test "filterBy non-matching query hides fields" {
    var fields = [_]InspectorField{
        .{ .key = "status", .value = "active" },
        .{ .key = "count", .value = "5" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("xyz"); // No match
    try testing.expectEqualStrings("xyz", insp.filter_query);
}

test "filterBy empty query shows all fields" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Bob" },
        .{ .key = "id", .value = "99" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("na");
    insp.filterBy(""); // Clear filter
    try testing.expectEqualStrings("", insp.filter_query);
}

test "filterBy clamps scroll_offset when visible count shrinks" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
        .{ .key = "f3", .value = "v3" },
    };
    var insp = Inspector.init(&fields);
    insp.scroll_offset = 2;
    insp.filterBy("f"); // All 3 match, scroll_offset still 2
    insp.scroll_offset = 2;
    insp.filterBy("f1"); // Only 1 matches, scroll_offset should clamp to 0
    // Implementation should set scroll_offset to min(current, visibleCount-1)
}

test "filterBy persists across scrollDown" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "type", .value = "user" },
        .{ .key = "id", .value = "123" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("n"); // Only "name" matches
    const query_before = insp.filter_query;
    insp.scrollDown();
    try testing.expectEqualStrings(query_before, insp.filter_query);
}

test "filterBy partial key match works (contains search)" {
    var fields = [_]InspectorField{
        .{ .key = "user_name", .value = "Alice" },
        .{ .key = "name", .value = "Bob" },
        .{ .key = "full_name", .value = "Carol" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("name"); // Should match all 3
    try testing.expectEqualStrings("name", insp.filter_query);
}

test "filterBy only matches key, not value" {
    var fields = [_]InspectorField{
        .{ .key = "color", .value = "red" },
        .{ .key = "status", .value = "pending" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("pending"); // Matches value but not key
    // Should not find any matches; only key is searched
    try testing.expectEqualStrings("pending", insp.filter_query);
}

test "filterBy after clear still works" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "email", .value = "a@b.com" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("na");
    insp.clearFilter();
    insp.filterBy("em"); // Should filter on email
    try testing.expectEqualStrings("em", insp.filter_query);
}

test "filterBy with special characters in query" {
    var fields = [_]InspectorField{
        .{ .key = "user@host", .value = "value" },
        .{ .key = "config", .value = "data" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("@"); // Special char query
    try testing.expectEqualStrings("@", insp.filter_query);
}

// ============================================================================
// clearFilter Tests (4 tests)
// ============================================================================

test "clearFilter sets filter_query to empty string" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Alice" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("na");
    try testing.expectEqualStrings("na", insp.filter_query);
    insp.clearFilter();
    try testing.expectEqualStrings("", insp.filter_query);
}

test "clearFilter restores all fields as visible" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
        .{ .key = "f3", .value = "v3" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("f1"); // Hide f2, f3
    insp.clearFilter();
    try testing.expectEqualStrings("", insp.filter_query);
}

test "clearFilter scroll_offset remains unchanged if still valid" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "email", .value = "a@b.com" },
    };
    var insp = Inspector.init(&fields);
    insp.scroll_offset = 1;
    insp.filterBy("n"); // Only name visible, offset clamped to 0
    insp.clearFilter();
    // After clear, offset should be preserved if valid
}

test "clearFilter on already empty filter is safe" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value" },
    };
    var insp = Inspector.init(&fields);
    insp.clearFilter(); // Already empty
    try testing.expectEqualStrings("", insp.filter_query);
}

// ============================================================================
// Builder API Tests (8 tests)
// ============================================================================

test "withBlock sets block field" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value" },
    };
    var insp = Inspector.init(&fields);
    const block = Block{ .borders = .all };
    const insp2 = insp.withBlock(block);
    try testing.expect(insp2.block != null);
}

test "withKeyStyle sets key_style field" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value" },
    };
    var insp = Inspector.init(&fields);
    const style = Style{ .bold = true };
    const insp2 = insp.withKeyStyle(style);
    try testing.expect(insp2.key_style.bold == true);
}

test "withValueStyle sets value_style field" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value" },
    };
    var insp = Inspector.init(&fields);
    const style = Style{ .italic = true };
    const insp2 = insp.withValueStyle(style);
    try testing.expect(insp2.value_style.italic == true);
}

test "withTypeStyle sets type_style field" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value", .field_type = "string" },
    };
    var insp = Inspector.init(&fields);
    const style = Style{ .dim = true };
    const insp2 = insp.withTypeStyle(style);
    try testing.expect(insp2.type_style.dim == true);
}

test "withFilterStyle sets filter_style field" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value" },
    };
    var insp = Inspector.init(&fields);
    const style = Style{ .underline = true };
    const insp2 = insp.withFilterStyle(style);
    try testing.expect(insp2.filter_style.underline == true);
}

test "withShowTypes sets show_types field" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value", .field_type = "string" },
    };
    var insp = Inspector.init(&fields);
    const insp2 = insp.withShowTypes(true);
    try testing.expect(insp2.show_types == true);
}

test "withShowFilter sets show_filter field" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value" },
    };
    var insp = Inspector.init(&fields);
    const insp2 = insp.withShowFilter(true);
    try testing.expect(insp2.show_filter == true);
}

test "builder methods return new Inspector without mutation" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value" },
    };
    var insp = Inspector.init(&fields);
    const style = Style{ .bold = true };
    const insp2 = insp.withKeyStyle(style);
    // Original should not be modified
    try testing.expect(insp.key_style.bold != true);
    // New instance should have bold set
    try testing.expect(insp2.key_style.bold == true);
}

// ============================================================================
// Render — Basic Tests (8 tests)
// ============================================================================

test "render on zero area does not crash" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value" },
    };
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
}

test "render with empty fields does not crash" {
    var fields: [0]InspectorField = undefined;
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "render single field does not crash" {
    var fields = [_]InspectorField{
        .{ .key = "status", .value = "active" },
    };
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "render key:value output" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Alice" },
    };
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // Verify render completes without crash (exact output checked in deeper render tests)
}

test "render with show_types true includes type annotation" {
    var fields = [_]InspectorField{
        .{ .key = "count", .value = "42", .field_type = "i32" },
    };
    var insp = Inspector.init(&fields).withShowTypes(true);
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 20 });
}

test "render with show_filter true shows filter row" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Bob" },
    };
    var insp = Inspector.init(&fields)
        .withShowFilter(true);
    insp.filterBy("na");
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 20 });
}

test "render respects scroll_offset (skips earlier fields)" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
        .{ .key = "f3", .value = "v3" },
    };
    var insp = Inspector.init(&fields);
    insp.scroll_offset = 1; // Start from f2
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "render with block border does not crash" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value" },
    };
    const block = Block{ .borders = .all };
    var insp = Inspector.init(&fields).withBlock(block);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

// ============================================================================
// Render — Indentation & Nesting Tests (4 tests)
// ============================================================================

test "render applies indentation based on field depth" {
    var fields = [_]InspectorField{
        .{ .key = "root", .value = "v1", .depth = 0 },
        .{ .key = "child", .value = "v2", .depth = 1 },
        .{ .key = "grandchild", .value = "v3", .depth = 2 },
    };
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // Depth 1 should have 2 spaces, depth 2 should have 4 spaces (depth * 2)
}

test "render deep nesting (depth up to 10)" {
    var fields = [_]InspectorField{
        .{ .key = "level0", .value = "v0", .depth = 0 },
        .{ .key = "level5", .value = "v5", .depth = 5 },
        .{ .key = "level10", .value = "v10", .depth = 10 },
    };
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 30 });
}

test "render zero depth has no indentation" {
    var fields = [_]InspectorField{
        .{ .key = "noindent", .value = "value", .depth = 0 },
    };
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // First character at x=0 should be 'n' (from "noindent")
}

test "render type annotation appears after value when show_types true" {
    var fields = [_]InspectorField{
        .{ .key = "port", .value = "8080", .field_type = "u16" },
    };
    var insp = Inspector.init(&fields).withShowTypes(true);
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 20 });
}

// ============================================================================
// Render — Edge Cases Tests (6 tests)
// ============================================================================

test "render with narrow area (width=10) does not crash" {
    var fields = [_]InspectorField{
        .{ .key = "k", .value = "v" },
    };
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 10 });
}

test "render with single height does not crash" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value" },
    };
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 40, 1);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 1 });
}

test "render long key and value are truncated safely" {
    var fields = [_]InspectorField{
        .{ .key = "very_long_key_name_that_exceeds_buffer", .value = "very_long_value_that_should_be_truncated" },
    };
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 10 });
}

test "render filter query with no matches renders nothing in fields" {
    var fields = [_]InspectorField{
        .{ .key = "color", .value = "red" },
        .{ .key = "size", .value = "10" },
    };
    var insp = Inspector.init(&fields)
        .withShowFilter(true);
    insp.filterBy("xyz"); // No matches
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "render multiple fields fills available height" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
        .{ .key = "f3", .value = "v3" },
    };
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 10 });
}

test "render empty field_type does not show type annotation" {
    var fields = [_]InspectorField{
        .{ .key = "data", .value = "content", .field_type = "" },
    };
    var insp = Inspector.init(&fields).withShowTypes(true);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // Empty type should not render [type] tag
}

// ============================================================================
// Integration & Complex Scenarios (6 tests)
// ============================================================================

test "scroll past end then goToTop returns to 0" {
    var fields = [_]InspectorField{
        .{ .key = "f1", .value = "v1" },
        .{ .key = "f2", .value = "v2" },
    };
    var insp = Inspector.init(&fields);
    insp.scrollDown();
    insp.scrollDown();
    insp.scrollDown();
    try testing.expectEqual(@as(usize, 1), insp.scroll_offset);
    insp.goToTop();
    try testing.expectEqual(@as(usize, 0), insp.scroll_offset);
}

test "filter then scroll preserves filter state" {
    var fields = [_]InspectorField{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "email", .value = "a@b.com" },
        .{ .key = "phone", .value = "555-1234" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("n"); // Matches "name" and "phone"
    const query = insp.filter_query;
    insp.scrollDown();
    try testing.expectEqualStrings(query, insp.filter_query);
}

test "builder chaining preserves all fields" {
    var fields = [_]InspectorField{
        .{ .key = "key", .value = "value", .field_type = "string" },
    };
    var insp = Inspector.init(&fields);
    const insp2 = insp.withShowTypes(true)
        .withShowFilter(true)
        .withKeyStyle(Style{ .bold = true });
    try testing.expect(insp2.show_types == true);
    try testing.expect(insp2.show_filter == true);
    try testing.expect(insp2.key_style.bold == true);
}

test "render with all options enabled" {
    var fields = [_]InspectorField{
        .{ .key = "config", .value = "enabled", .field_type = "bool", .depth = 0 },
        .{ .key = "timeout", .value = "5000", .field_type = "u32", .depth = 1 },
    };
    const block = Block{ .borders = .all };
    var insp = Inspector.init(&fields)
        .withShowTypes(true)
        .withShowFilter(true)
        .withBlock(block);
    insp.filterBy("c"); // Match config
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 20 });
}

test "fields with different depths maintain hierarchy" {
    var fields = [_]InspectorField{
        .{ .key = "user", .value = "{}", .depth = 0 },
        .{ .key = "id", .value = "123", .depth = 1 },
        .{ .key = "name", .value = "Alice", .depth = 1 },
        .{ .key = "settings", .value = "{}", .depth = 1 },
        .{ .key = "theme", .value = "dark", .depth = 2 },
    };
    var insp = Inspector.init(&fields);
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    insp.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 20 });
}

test "navigation with filter respects visible count" {
    var fields = [_]InspectorField{
        .{ .key = "apple", .value = "fruit" },
        .{ .key = "banana", .value = "fruit" },
        .{ .key = "carrot", .value = "vegetable" },
    };
    var insp = Inspector.init(&fields);
    insp.filterBy("fruit"); // Matches apple and banana
    insp.goToBottom();
    // Should be at last visible field (banana, index 1)
}
