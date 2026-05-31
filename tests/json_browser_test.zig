//! JsonBrowser tests — v2.16.0
//!
//! Tests collapsible JSON tree rendering, cursor navigation, and collapse logic.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;

const JsonBrowser = sailor.tui.widgets.JsonBrowser;
const Node = sailor.tui.widgets.JsonBrowserNode;
const NodeKind = sailor.tui.widgets.JsonBrowserNodeKind;

fn makeBuffer(allocator: std.mem.Allocator, w: u16, h: u16) !Buffer {
    return Buffer.init(allocator, Rect{ .x = 0, .y = 0, .width = w, .height = h });
}

// ============================================================================
// NodeKind
// ============================================================================

test "NodeKind values are distinct" {
    try testing.expect(NodeKind.object_open != NodeKind.object_close);
    try testing.expect(NodeKind.array_open != NodeKind.array_close);
    try testing.expect(NodeKind.string != NodeKind.number);
    try testing.expect(NodeKind.boolean != NodeKind.null_val);
}

// ============================================================================
// Default state
// ============================================================================

test "default cursor and scroll are zero" {
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0 },
        .{ .kind = .object_close, .depth = 0 },
    };
    const b = JsonBrowser{ .nodes = &nodes };
    try testing.expectEqual(@as(usize, 0), b.cursor);
    try testing.expectEqual(@as(u16, 0), b.scroll);
}

// ============================================================================
// toggleCollapse
// ============================================================================

test "toggleCollapse — object_open toggles" {
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0, .collapsed = false },
        .{ .kind = .string, .key = "x", .value = "\"v\"", .depth = 1 },
        .{ .kind = .object_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    b.toggleCollapse();
    try testing.expect(nodes[0].collapsed);
    b.toggleCollapse();
    try testing.expect(!nodes[0].collapsed);
}

test "toggleCollapse — array_open toggles" {
    var nodes = [_]Node{
        .{ .kind = .array_open, .depth = 0, .collapsed = false },
        .{ .kind = .number, .value = "1", .depth = 1 },
        .{ .kind = .array_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    b.toggleCollapse();
    try testing.expect(nodes[0].collapsed);
}

test "toggleCollapse — leaf node is no-op" {
    var nodes = [_]Node{
        .{ .kind = .string, .value = "\"hi\"", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    b.toggleCollapse();
    try testing.expect(!nodes[0].collapsed);
}

test "toggleCollapse — close bracket is no-op" {
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0 },
        .{ .kind = .object_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes, .cursor = 1 };
    b.toggleCollapse();
    try testing.expect(!nodes[1].collapsed);
}

test "toggleCollapse — out-of-bounds cursor is safe" {
    var nodes = [_]Node{};
    var b = JsonBrowser{ .nodes = &nodes, .cursor = 0 };
    b.toggleCollapse(); // no-op, no crash
}

// ============================================================================
// moveDown / moveUp — no collapse
// ============================================================================

test "moveDown — visits all nodes in order" {
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0 },
        .{ .kind = .string, .key = "a", .value = "\"1\"", .depth = 1 },
        .{ .kind = .string, .key = "b", .value = "\"2\"", .depth = 1 },
        .{ .kind = .object_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    b.moveDown();
    try testing.expectEqual(@as(usize, 1), b.cursor);
    b.moveDown();
    try testing.expectEqual(@as(usize, 2), b.cursor);
    b.moveDown();
    try testing.expectEqual(@as(usize, 3), b.cursor);
    b.moveDown(); // at end — stays
    try testing.expectEqual(@as(usize, 3), b.cursor);
}

test "moveUp — traverses backwards" {
    var nodes = [_]Node{
        .{ .kind = .array_open, .depth = 0 },
        .{ .kind = .number, .value = "1", .depth = 1 },
        .{ .kind = .array_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes, .cursor = 2 };
    b.moveUp();
    try testing.expectEqual(@as(usize, 1), b.cursor);
    b.moveUp();
    try testing.expectEqual(@as(usize, 0), b.cursor);
    b.moveUp(); // at top — stays
    try testing.expectEqual(@as(usize, 0), b.cursor);
}

test "moveDown then moveUp returns to start" {
    var nodes = [_]Node{
        .{ .kind = .number, .value = "1", .depth = 0 },
        .{ .kind = .number, .value = "2", .depth = 0 },
        .{ .kind = .number, .value = "3", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    b.moveDown();
    b.moveDown();
    try testing.expectEqual(@as(usize, 2), b.cursor);
    b.moveUp();
    b.moveUp();
    try testing.expectEqual(@as(usize, 0), b.cursor);
}

// ============================================================================
// moveDown / moveUp — with collapse
// ============================================================================

test "moveDown — skips collapsed children" {
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0 },
        .{ .kind = .object_open, .key = "inner", .depth = 1, .collapsed = true },
        .{ .kind = .string, .key = "x", .value = "\"hi\"", .depth = 2 }, // hidden
        .{ .kind = .object_close, .depth = 1 },                          // hidden
        .{ .kind = .number, .key = "n", .value = "42", .depth = 1 },
        .{ .kind = .object_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    b.moveDown();
    try testing.expectEqual(@as(usize, 1), b.cursor); // inner (visible as collapsed header)
    b.moveDown();
    try testing.expectEqual(@as(usize, 4), b.cursor); // n: 42 (nodes 2&3 skipped)
    b.moveDown();
    try testing.expectEqual(@as(usize, 5), b.cursor);
}

test "moveUp — skips collapsed children" {
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0 },
        .{ .kind = .object_open, .key = "inner", .depth = 1, .collapsed = true },
        .{ .kind = .string, .key = "x", .value = "\"hi\"", .depth = 2 }, // hidden
        .{ .kind = .object_close, .depth = 1 },                          // hidden
        .{ .kind = .number, .key = "n", .value = "42", .depth = 1 },
        .{ .kind = .object_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes, .cursor = 5 };
    b.moveUp();
    try testing.expectEqual(@as(usize, 4), b.cursor);
    b.moveUp();
    try testing.expectEqual(@as(usize, 1), b.cursor); // inner collapsed header (nodes 2&3 skipped)
    b.moveUp();
    try testing.expectEqual(@as(usize, 0), b.cursor);
}

test "moveDown — deeply nested collapse skips all descendants" {
    // Object with nested object, inner collapsed
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0, .collapsed = true }, // cursor starts here
        .{ .kind = .object_open, .key = "a", .depth = 1 },        // hidden
        .{ .kind = .number, .key = "b", .value = "1", .depth = 2 }, // hidden
        .{ .kind = .object_close, .depth = 1 },                    // hidden
        .{ .kind = .object_close, .depth = 0 },                    // hidden (matching close)
        .{ .kind = .number, .value = "99", .depth = 0 },           // visible sibling
    };
    var b = JsonBrowser{ .nodes = &nodes };
    b.moveDown();
    // After the root collapsed object, next visible is node 5 (sibling at depth 0)
    try testing.expectEqual(@as(usize, 5), b.cursor);
}

test "toggle then navigate — collapse updates navigation" {
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0 },
        .{ .kind = .object_open, .key = "inner", .depth = 1 },
        .{ .kind = .string, .key = "x", .value = "\"v\"", .depth = 2 },
        .{ .kind = .object_close, .depth = 1 },
        .{ .kind = .number, .key = "n", .value = "42", .depth = 1 },
        .{ .kind = .object_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    b.moveDown(); // cursor=1 (inner)
    b.toggleCollapse(); // collapse inner
    b.moveDown(); // should skip to n: 42 at index 4
    try testing.expectEqual(@as(usize, 4), b.cursor);
}

// ============================================================================
// Render — basic
// ============================================================================

test "render — empty node list is safe" {
    var b = JsonBrowser{ .nodes = &.{} };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
}

test "render — zero width is safe" {
    var nodes = [_]Node{ .{ .kind = .number, .value = "1", .depth = 0 } };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 5 });
}

test "render — zero height is safe" {
    var nodes = [_]Node{ .{ .kind = .number, .value = "1", .depth = 0 } };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 0 });
}

test "render — object brackets" {
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0 },
        .{ .kind = .object_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
    try testing.expectEqual(@as(u21, '{'), buf.get(0, 0).char);
    try testing.expectEqual(@as(u21, '}'), buf.get(0, 1).char);
}

test "render — array brackets" {
    var nodes = [_]Node{
        .{ .kind = .array_open, .depth = 0 },
        .{ .kind = .array_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
    try testing.expectEqual(@as(u21, '['), buf.get(0, 0).char);
    try testing.expectEqual(@as(u21, ']'), buf.get(0, 1).char);
}

test "render — string value uses string_style" {
    var nodes = [_]Node{
        .{ .kind = .string, .value = "\"hello\"", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });
    try testing.expectEqual(Color.green, buf.get(0, 0).style.fg.?);
    try testing.expectEqual(@as(u21, '"'), buf.get(0, 0).char);
}

test "render — number uses number_style" {
    var nodes = [_]Node{
        .{ .kind = .number, .value = "42", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
    try testing.expectEqual(Color.cyan, buf.get(0, 0).style.fg.?);
    try testing.expectEqual(@as(u21, '4'), buf.get(0, 0).char);
}

test "render — boolean uses bool_style" {
    var nodes = [_]Node{
        .{ .kind = .boolean, .value = "true", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
    try testing.expectEqual(Color.yellow, buf.get(0, 0).style.fg.?);
    try testing.expectEqual(@as(u21, 't'), buf.get(0, 0).char);
}

test "render — null_val renders 'null' with null_style" {
    var nodes = [_]Node{
        .{ .kind = .null_val, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
    try testing.expectEqual(@as(u21, 'n'), buf.get(0, 0).char);
    try testing.expectEqual(Color.bright_black, buf.get(0, 0).style.fg.?);
}

test "render — key printed before value with ': ' separator" {
    var nodes = [_]Node{
        .{ .kind = .number, .key = "x", .value = "7", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });
    // "x: 7" — key='x', colon, space, then value
    try testing.expectEqual(@as(u21, 'x'), buf.get(0, 0).char);
    try testing.expectEqual(@as(u21, ':'), buf.get(1, 0).char);
    try testing.expectEqual(@as(u21, ' '), buf.get(2, 0).char);
    try testing.expectEqual(@as(u21, '7'), buf.get(3, 0).char);
}

test "render — null_val with key" {
    var nodes = [_]Node{
        .{ .kind = .null_val, .key = "data", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });
    // "data: null"
    try testing.expectEqual(@as(u21, 'd'), buf.get(0, 0).char);
    try testing.expectEqual(@as(u21, 'n'), buf.get(6, 0).char); // "data: " = 6 chars
}

test "render — depth 2 indents by 4 spaces (default 2-space indent)" {
    var nodes = [_]Node{
        .{ .kind = .number, .value = "1", .depth = 2 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).char);
    try testing.expectEqual(@as(u21, ' '), buf.get(1, 0).char);
    try testing.expectEqual(@as(u21, ' '), buf.get(2, 0).char);
    try testing.expectEqual(@as(u21, ' '), buf.get(3, 0).char);
    try testing.expectEqual(@as(u21, '1'), buf.get(4, 0).char);
}

test "render — cursor node uses cursor_style" {
    var nodes = [_]Node{
        .{ .kind = .number, .value = "42", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes, .cursor = 0 };
    b.cursor_style = .{ .fg = .red, .bold = true };
    var buf = try makeBuffer(testing.allocator, 10, 3);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 3 });
    const cell = buf.get(0, 0);
    try testing.expectEqual(Color.red, cell.style.fg.?);
    try testing.expect(cell.style.bold);
}

test "render — non-cursor node does not use cursor_style" {
    var nodes = [_]Node{
        .{ .kind = .number, .value = "1", .depth = 0 },
        .{ .kind = .number, .value = "2", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes, .cursor = 0 };
    b.cursor_style = .{ .fg = .red };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
    // Row 1 (node index 1) should NOT be red
    try testing.expect(buf.get(0, 1).style.fg != Color.red);
}

// ============================================================================
// Render — collapse
// ============================================================================

test "render — collapsed object shows { ... }" {
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0, .collapsed = true },
        .{ .kind = .string, .key = "x", .value = "\"v\"", .depth = 1 },
        .{ .kind = .object_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });

    // Only row 0 should be rendered — "{ ... }"
    try testing.expectEqual(@as(u21, '{'), buf.get(0, 0).char);
    try testing.expectEqual(@as(u21, '.'), buf.get(2, 0).char); // "{ ... }"[2] = '.'
    // Row 1 should be empty (children and close bracket hidden)
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 1).char);
}

test "render — collapsed array shows [ ... ]" {
    var nodes = [_]Node{
        .{ .kind = .array_open, .key = "arr", .depth = 0, .collapsed = true },
        .{ .kind = .number, .value = "1", .depth = 1 },
        .{ .kind = .array_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });

    // "arr: [ ... ]" — '[' at col 5
    try testing.expectEqual(@as(u21, '['), buf.get(5, 0).char);
    // Row 1 should be empty
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 1).char);
}

test "render — sibling after collapsed object is visible" {
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0 },
        .{ .kind = .object_open, .key = "a", .depth = 1, .collapsed = true },
        .{ .kind = .string, .key = "x", .value = "\"v\"", .depth = 2 }, // hidden
        .{ .kind = .object_close, .depth = 1 },                          // hidden
        .{ .kind = .number, .key = "b", .value = "99", .depth = 1 },    // visible
        .{ .kind = .object_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 20, 10);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });

    // Row 0: '{'
    try testing.expectEqual(@as(u21, '{'), buf.get(0, 0).char);
    // Row 1: "  a: { ... }" — collapsed inner object
    try testing.expectEqual(@as(u21, '{'), buf.get(4, 1).char); // "  a: {"
    // Row 2: "  b: 99" — sibling (hidden nodes 2&3 skipped)
    try testing.expectEqual(@as(u21, 'b'), buf.get(2, 2).char);
}

test "render — nested collapse hides all descendants" {
    var nodes = [_]Node{
        .{ .kind = .object_open, .depth = 0, .collapsed = true }, // collapsed root
        .{ .kind = .object_open, .key = "a", .depth = 1 },
        .{ .kind = .number, .key = "b", .value = "1", .depth = 2 },
        .{ .kind = .object_close, .depth = 1 },
        .{ .kind = .object_close, .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });

    // Only row 0: "{ ... }"
    try testing.expectEqual(@as(u21, '{'), buf.get(0, 0).char);
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 1).char);
}

// ============================================================================
// Render — scroll
// ============================================================================

test "render — scroll hides top visible lines" {
    var nodes = [_]Node{
        .{ .kind = .number, .value = "1", .depth = 0 },
        .{ .kind = .number, .value = "2", .depth = 0 },
        .{ .kind = .number, .value = "3", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes, .scroll = 1 };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
    // Row 0 now shows "2" (first visible after scroll)
    try testing.expectEqual(@as(u21, '2'), buf.get(0, 0).char);
}

test "render — scroll past all content renders nothing" {
    var nodes = [_]Node{
        .{ .kind = .number, .value = "1", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes, .scroll = 100 };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).char);
}

// ============================================================================
// Render — area offset
// ============================================================================

test "render — content placed at area offset" {
    var nodes = [_]Node{
        .{ .kind = .number, .value = "7", .depth = 0 },
    };
    var b = JsonBrowser{ .nodes = &nodes };
    var buf = try makeBuffer(testing.allocator, 20, 10);
    defer buf.deinit(testing.allocator);
    b.render(&buf, Rect{ .x = 5, .y = 3, .width = 10, .height = 5 });
    try testing.expectEqual(@as(u21, '7'), buf.get(5, 3).char);
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).char);
}
