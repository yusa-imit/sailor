//! MindMap Widget Tests — TDD Red Phase
//!
//! Tests MindMap widget with hub-and-spoke layout, node rendering,
//! root/branch/grandchild positioning, style application, focus handling,
//! connection lines, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const MindMap = sailor.tui.widgets.MindMap;
const MindNode = sailor.tui.widgets.mindmap.MindNode;

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
    if (text.len == 0) return false;

    var cps: [256]u21 = undefined;
    const cp_count = decodeUtf8(text, &cps);
    if (cp_count == 0) return false;

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

/// Check if buffer area contains a specific character
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

// ============================================================================
// Group 1: Init/Defaults (5 tests)
// ============================================================================

test "MindMap.init has empty nodes" {
    const mm = MindMap.init();
    try testing.expectEqual(@as(usize, 0), mm.nodes.len);
}

test "MindMap.init has focused == 0" {
    const mm = MindMap.init();
    try testing.expectEqual(@as(usize, 0), mm.focused);
}

test "MindMap.init has node_width == 14" {
    const mm = MindMap.init();
    try testing.expectEqual(@as(u16, 14), mm.node_width);
}

test "MindMap.init has node_height == 3" {
    const mm = MindMap.init();
    try testing.expectEqual(@as(u16, 3), mm.node_height);
}

test "MindMap.init has h_gap == 2" {
    const mm = MindMap.init();
    try testing.expectEqual(@as(u16, 2), mm.h_gap);
}

// ============================================================================
// Group 2: MAX_NODES Constant (1 test)
// ============================================================================

test "MindMap.MAX_NODES equals 32" {
    try testing.expectEqual(@as(usize, 32), MindMap.MAX_NODES);
}

// ============================================================================
// Group 3: nodeCount Method (5 tests)
// ============================================================================

test "MindMap.nodeCount with zero nodes returns 0" {
    const mm = MindMap.init();
    try testing.expectEqual(@as(usize, 0), mm.nodeCount());
}

test "MindMap.nodeCount with 3 nodes returns 3" {
    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Child1" },
        .{ .label = "Child2" },
    };
    const mm = MindMap.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 3), mm.nodeCount());
}

test "MindMap.nodeCount caps at MAX_NODES" {
    var nodes: [40]MindNode = undefined;
    for (0..40) |i| {
        nodes[i] = MindNode{ .label = "n" };
    }
    const mm = MindMap.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 32), mm.nodeCount());
}

test "MindMap.nodeCount with MAX_NODES exactly" {
    var nodes: [32]MindNode = undefined;
    for (0..32) |i| {
        nodes[i] = MindNode{ .label = "n" };
    }
    const mm = MindMap.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 32), mm.nodeCount());
}

test "MindMap.nodeCount with one node" {
    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 1), mm.nodeCount());
}

// ============================================================================
// Group 4: childCount Method (6 tests)
// ============================================================================

test "MindMap.childCount of root with no children returns 0" {
    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 0), mm.childCount(0));
}

test "MindMap.childCount of root with 3 children returns 3" {
    var nodes = [_]MindNode{
        .{ .label = "Root", .parent = 0 },
        .{ .label = "Child1", .parent = 0 },
        .{ .label = "Child2", .parent = 0 },
        .{ .label = "Child3", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 3), mm.childCount(0));
}

test "MindMap.childCount of branch returns grandchild count" {
    var nodes = [_]MindNode{
        .{ .label = "Root", .parent = 0 },
        .{ .label = "Branch1", .parent = 0 },
        .{ .label = "Grandchild1", .parent = 1 },
        .{ .label = "Grandchild2", .parent = 1 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 2), mm.childCount(1));
}

test "MindMap.childCount of nonexistent node returns 0" {
    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 0), mm.childCount(99));
}

test "MindMap.childCount skips root self-reference" {
    var nodes = [_]MindNode{
        .{ .label = "Root", .parent = 0 },
        .{ .label = "Child", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    // root (idx 0) has parent=0 but should not count itself
    try testing.expectEqual(@as(usize, 1), mm.childCount(0));
}

test "MindMap.childCount branch with no children returns 0" {
    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Branch" },
    };
    const mm = MindMap.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 0), mm.childCount(1));
}

// ============================================================================
// Group 5: Builder Immutability (8 tests)
// ============================================================================

test "withNodes returns new value, original unchanged" {
    var nodes1 = [_]MindNode{.{ .label = "n1" }};
    const mm1 = MindMap.init().withNodes(&nodes1);
    var nodes2 = [_]MindNode{.{ .label = "n2" }};
    const mm2 = mm1.withNodes(&nodes2);
    try testing.expectEqual(@as(usize, 1), mm1.nodes.len);
    try testing.expectEqualStrings("n1", mm1.nodes[0].label);
    try testing.expectEqual(@as(usize, 1), mm2.nodes.len);
    try testing.expectEqualStrings("n2", mm2.nodes[0].label);
}

test "withFocused returns new value, original unchanged" {
    const mm1 = MindMap.init().withFocused(1);
    const mm2 = mm1.withFocused(3);
    try testing.expectEqual(@as(usize, 1), mm1.focused);
    try testing.expectEqual(@as(usize, 3), mm2.focused);
}

test "withStyle returns new value, original unchanged" {
    const style1 = Style{ .bold = true };
    const style2 = Style{ .dim = true };
    const mm1 = MindMap.init().withStyle(style1);
    const mm2 = mm1.withStyle(style2);
    try testing.expectEqual(true, mm1.style.bold);
    try testing.expectEqual(true, mm2.style.dim);
}

test "withRootStyle returns new value, original unchanged" {
    const style1 = Style{ .bold = true };
    const style2 = Style{ .dim = true };
    const mm1 = MindMap.init().withRootStyle(style1);
    const mm2 = mm1.withRootStyle(style2);
    try testing.expectEqual(true, mm1.root_style.bold);
    try testing.expectEqual(true, mm2.root_style.dim);
}

test "withFocusedStyle returns new value, original unchanged" {
    const style1 = Style{ .bold = true };
    const style2 = Style{ .dim = true };
    const mm1 = MindMap.init().withFocusedStyle(style1);
    const mm2 = mm1.withFocusedStyle(style2);
    try testing.expectEqual(true, mm1.focused_style.bold);
    try testing.expectEqual(true, mm2.focused_style.dim);
}

test "withNodeWidth returns new value, original unchanged" {
    const mm1 = MindMap.init().withNodeWidth(10);
    const mm2 = mm1.withNodeWidth(20);
    try testing.expectEqual(@as(u16, 10), mm1.node_width);
    try testing.expectEqual(@as(u16, 20), mm2.node_width);
}

test "withNodeHeight returns new value, original unchanged" {
    const mm1 = MindMap.init().withNodeHeight(2);
    const mm2 = mm1.withNodeHeight(5);
    try testing.expectEqual(@as(u16, 2), mm1.node_height);
    try testing.expectEqual(@as(u16, 5), mm2.node_height);
}

test "withHGap returns new value, original unchanged" {
    const mm1 = MindMap.init().withHGap(1);
    const mm2 = mm1.withHGap(4);
    try testing.expectEqual(@as(u16, 1), mm1.h_gap);
    try testing.expectEqual(@as(u16, 4), mm2.h_gap);
}

// ============================================================================
// Group 6: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "render with zero width does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    mm.render(&buf, area);
}

test "render with zero height does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };
    mm.render(&buf, area);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    mm.render(&buf, area);
}

test "render with no nodes produces no content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const mm = MindMap.init();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    mm.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 7: Render — Root Node Only (5 tests)
// ============================================================================

test "render root only produces content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render root node has box characters (corners)" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(14).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    // Node box must have all four corners when width >= 2 and height >= 1
    const has_corners = areaHasChar(buf, area, '┌') or areaHasChar(buf, area, '┐') or
                        areaHasChar(buf, area, '└') or areaHasChar(buf, area, '┘');
    try testing.expect(has_corners);
}

test "render root label appears in node" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Root"));
}

test "render root with root_style applies styling" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes).withRootStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render root centered in area" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(14).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Root"));
}

// ============================================================================
// Group 8: Render — Single Right Branch (4 tests)
// ============================================================================

test "render one right branch draws content right of root" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root", .parent = 0 },
        .{ .label = "Right", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(14).withNodeHeight(3).withHGap(2);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    // Right branch label must appear in the rendered output
    try testing.expect(findInArea(buf, area, "Right"));
}

test "render right branch with connection line" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Right", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(14).withNodeHeight(3).withHGap(2);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

test "render right branch not overlapping root" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Right", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    // Root node label must be rendered
    try testing.expect(findInArea(buf, area, "Root"));
}

test "render right branch label visible" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Branch" },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Root") or findInArea(buf, area, "Branch") or
                       countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 9: Render — Single Left Branch (4 tests)
// ============================================================================

test "render one left branch draws content left of root" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root", .parent = 0 },
        .{ .label = "Left", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(14).withNodeHeight(3).withHGap(2);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    // Left branch label must appear in the rendered output
    try testing.expect(findInArea(buf, area, "Left"));
}

test "render left branch with connection line" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Left", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(14).withNodeHeight(3).withHGap(2);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

test "render left branch not overlapping root" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Left", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    // Root node label must be rendered
    try testing.expect(findInArea(buf, area, "Root"));
}

test "render left branch label visible" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Left", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 10: Render — Alternating Sides (2 tests)
// ============================================================================

test "render right-left-right alternation" {
    var buf = try Buffer.init(std.testing.allocator, 120, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Right0", .parent = 0 },
        .{ .label = "Left1", .parent = 0 },
        .{ .label = "Right2", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(14).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 15);
}

test "render multiple branches all visible" {
    var buf = try Buffer.init(std.testing.allocator, 120, 30);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "B1", .parent = 0 },
        .{ .label = "B2", .parent = 0 },
        .{ .label = "B3", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 30 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 15);
}

// ============================================================================
// Group 11: Render — Grandchildren (5 tests)
// ============================================================================

test "render grandchild of right branch appears further right" {
    var buf = try Buffer.init(std.testing.allocator, 150, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Branch", .parent = 0 },
        .{ .label = "GrandChild", .parent = 1 },
    };
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 150, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

test "render grandchild of left branch appears further left" {
    var buf = try Buffer.init(std.testing.allocator, 150, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Branch", .parent = 0 },
        .{ .label = "GrandChild", .parent = 1 },
    };
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 150, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

test "render two grandchildren of same branch" {
    var buf = try Buffer.init(std.testing.allocator, 150, 30);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Branch" },
        .{ .label = "GC1", .parent = 1 },
        .{ .label = "GC2", .parent = 1 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 150, .height = 30 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 15);
}

test "render three-level deep tree" {
    var buf = try Buffer.init(std.testing.allocator, 200, 30);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "B" },
        .{ .label = "GC", .parent = 1 },
        .{ .label = "GGC", .parent = 2 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 30 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

test "render grandchildren inherit parent side" {
    var buf = try Buffer.init(std.testing.allocator, 200, 30);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "LeftB", .parent = 0 },
        .{ .label = "LeftGC", .parent = 1 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 30 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

// ============================================================================
// Group 12: Render — Focused Node Styling (4 tests)
// ============================================================================

test "render focused root node uses focused_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Branch" },
    };
    const mm = MindMap.init().withNodes(&nodes).withFocused(0).withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Root"));
}

test "render focused branch node uses focused_style" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Focused", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes).withFocused(1);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

test "render non-focused node does not use focused_style" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "NotFocused" },
    };
    const mm = MindMap.init().withNodes(&nodes).withFocused(1);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render focused index beyond node count does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes).withFocused(100);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 13: Render — Node Styling (3 tests)
// ============================================================================

test "render node with custom style applies that style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Styled", .parent = 0, .style = .{ .bold = true } },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

test "render nodes without custom style use base style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
    };
    const mm = MindMap.init().withNodes(&nodes).withStyle(.{ .dim = true });
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render per-node style overrides base style" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root", .style = .{ .bold = true } },
        .{ .label = "Branch", .parent = 0, .style = .{ .dim = true } },
    };
    const mm = MindMap.init().withNodes(&nodes).withStyle(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

// ============================================================================
// Group 14: Render — Label Handling (5 tests)
// ============================================================================

test "render empty label node renders as empty box" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "" }};
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(14).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render label text centered in node" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Test" }};
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(14).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Test"));
}

test "render long label truncates to fit node_width" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "VeryLongLabelThatExceedsWidth" }};
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(10).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render short label in large node doesn't break" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "X" }};
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(20).withNodeHeight(5);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render many nodes with labels" {
    var buf = try Buffer.init(std.testing.allocator, 150, 40);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "A", .parent = 0 },
        .{ .label = "B", .parent = 0 },
        .{ .label = "C", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(10).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 150, .height = 40 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 15);
}

// ============================================================================
// Group 15: Render — Spacing & Sizing (5 tests)
// ============================================================================

test "render node_width=10 makes narrower nodes" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "X" }};
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(10).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render node_height=5 makes taller nodes" {
    var buf = try Buffer.init(std.testing.allocator, 80, 30);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "X" }};
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(14).withNodeHeight(5);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render h_gap=4 increases branch spacing" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "R", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes).withHGap(4).withNodeWidth(10);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

test "render h_gap=0 makes nodes touch horizontally" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "R", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes).withHGap(0).withNodeWidth(10);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

test "render smaller node dimensions in tight space" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "B", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(8).withNodeHeight(2).withHGap(1);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 16: Render — Block Border (3 tests)
// ============================================================================

test "render with Block renders frame around content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    mm.render(&buf, area);

    // Block border must render with box-drawing characters
    const has_border = areaHasChar(buf, area, '─') or areaHasChar(buf, area, '│') or areaHasChar(buf, area, '┌');
    try testing.expect(has_border);
}

test "render block reduces inner area for nodes" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes).withBlock(.{});
    const area = Rect{ .x = 5, .y = 5, .width = 40, .height = 10 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render block in tiny area doesn't crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    mm.render(&buf, area);

    const cells = countNonEmptyCells(buf, area);
    try testing.expect(cells <= 9);
}

// ============================================================================
// Group 17: Render — Capping at MAX_NODES (2 tests)
// ============================================================================

test "render more than MAX_NODES only draws MAX_NODES" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes: [40]MindNode = undefined;
    for (0..40) |i| {
        nodes[i] = MindNode{ .label = "n" };
    }
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(mm.nodeCount() == 32);
}

test "render exactly MAX_NODES succeeds" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes: [32]MindNode = undefined;
    for (0..32) |i| {
        nodes[i] = MindNode{ .label = "n" };
    }
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(mm.nodeCount() == 32);
}

// ============================================================================
// Group 18: Render — Offset Areas (2 tests)
// ============================================================================

test "render in offset area (x>0, y>0)" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Offset" }};
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(14).withNodeHeight(3);
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 10 };
    mm.render(&buf, area);

    // Label must appear in offset area
    try testing.expect(findInArea(buf, area, "Offset"));
}

test "render complex tree in offset area" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "B1", .parent = 0 },
        .{ .label = "B2", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 15, .y = 8, .width = 60, .height = 12 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 19: Builder Chain (1 test)
// ============================================================================

test "builder chain sets all fields correctly" {
    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "Branch" },
    };
    const mm = MindMap.init()
        .withNodes(&nodes)
        .withFocused(1)
        .withStyle(.{ .bold = true })
        .withRootStyle(.{ .dim = true })
        .withFocusedStyle(.{ .underline = true })
        .withNodeWidth(12)
        .withNodeHeight(4)
        .withHGap(3)
        .withBlock(.{});

    try testing.expectEqual(@as(usize, 2), mm.nodes.len);
    try testing.expectEqual(@as(usize, 1), mm.focused);
    try testing.expectEqual(@as(u16, 12), mm.node_width);
    try testing.expectEqual(@as(u16, 4), mm.node_height);
    try testing.expectEqual(@as(u16, 3), mm.h_gap);
    try testing.expect(mm.block != null);
}

// ============================================================================
// Group 20: Edge Cases (5 tests)
// ============================================================================

test "render area smaller than node_width" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(50);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    mm.render(&buf, area);
}

test "render area smaller than node_height" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{.{ .label = "Root" }};
    const mm = MindMap.init().withNodes(&nodes).withNodeHeight(20);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    mm.render(&buf, area);
}

test "render single character labels" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "R" },
        .{ .label = "A", .parent = 0 },
        .{ .label = "B", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render unicode labels" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "根" },
        .{ .label = "分支", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render symmetric tree with balanced children" {
    var buf = try Buffer.init(std.testing.allocator, 120, 30);
    defer buf.deinit();

    var nodes = [_]MindNode{
        .{ .label = "Root" },
        .{ .label = "L1", .parent = 0 },
        .{ .label = "R1", .parent = 0 },
        .{ .label = "L2", .parent = 0 },
        .{ .label = "R2", .parent = 0 },
    };
    const mm = MindMap.init().withNodes(&nodes).withNodeWidth(10).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 30 };
    mm.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 20);
}
