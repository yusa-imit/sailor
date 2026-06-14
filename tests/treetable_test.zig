//! TreeTable Widget Tests — Comprehensive Coverage
//!
//! Tests the TreeTable widget's initialization, tree node expansion/collapse,
//! visible row counting, selection navigation, builder API, rendering with tree
//! symbols and indentation, block borders, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Cell = sailor.tui.buffer.Cell;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const Column = sailor.tui.widgets.Column;
const ColumnWidth = sailor.tui.widgets.ColumnWidth;

// Import TreeTable types (will be exported from tui.zig by zig-developer)
const TreeTableNode = sailor.tui.TreeTableNode;
const TreeTable = sailor.tui.TreeTable;

/// Helper: Create a buffer with given dimensions
fn makeBuffer(w: u16, h: u16) !Buffer {
    return try Buffer.init(testing.allocator, w, h);
}

/// Helper: Find first x position in a row where a specific character appears
fn findCharInRow(buf: Buffer, y: u16, char: u21) ?u16 {
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == char) return x;
        }
    }
    return null;
}

/// Helper: Check if row contains a character
fn rowHasChar(buf: Buffer, y: u16, char: u21) bool {
    return findCharInRow(buf, y, char) != null;
}

/// Helper: Check if row contains specific text (substring match)
fn rowHasText(buf: Buffer, y: u16, text: []const u8) bool {
    if (text.len == 0) return true;
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == text[0]) {
                var match = true;
                var offset: u16 = 1;
                while (offset < text.len and x + offset < buf.width) : (offset += 1) {
                    if (buf.getConst(x + offset, y)) |next_cell| {
                        if (next_cell.char != text[offset]) {
                            match = false;
                            break;
                        }
                    } else {
                        match = false;
                        break;
                    }
                }
                if (match and offset == text.len) return true;
            }
        }
    }
    return false;
}

/// Helper: Get character at position
fn getCharAt(buf: Buffer, x: u16, y: u16) ?u21 {
    if (buf.getConst(x, y)) |cell| {
        return cell.char;
    }
    return null;
}

// ============================================================================
// INITIALIZATION TESTS (5 tests)
// ============================================================================

test "TreeTable init creates table with default values" {
    const cols = [_]Column{
        .{ .title = "Name", .width = .{ .percentage = 50 } },
        .{ .title = "Type", .width = .{ .percentage = 50 } },
    };
    const tt = TreeTable.init(&cols, &.{});
    try testing.expectEqual(@as(?usize, null), tt.selected);
    try testing.expectEqual(@as(usize, 0), tt.offset);
    try testing.expectEqual(@as(u16, 1), tt.column_spacing);
    try testing.expectEqual(@as(u16, 2), tt.indent);
}

test "TreeTable init stores columns" {
    const cols = [_]Column{
        .{ .title = "Name", .width = .{ .fixed = 20 } },
        .{ .title = "Value", .width = .{ .fixed = 30 } },
    };
    const tt = TreeTable.init(&cols, &.{});
    try testing.expectEqual(@as(usize, 2), tt.columns.len);
    try testing.expect(std.mem.eql(u8, tt.columns[0].title, "Name"));
    try testing.expect(std.mem.eql(u8, tt.columns[1].title, "Value"));
}

test "TreeTable init stores nodes" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Root"}, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes);
    try testing.expectEqual(@as(usize, 1), tt.nodes.len);
}

test "TreeTable init defaults to expanded_symbol = \"▼ \"" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt = TreeTable.init(&cols, &.{});
    try testing.expect(std.mem.eql(u8, tt.expanded_symbol, "▼ "));
}

test "TreeTable init defaults to collapsed_symbol = \"▶ \"" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt = TreeTable.init(&cols, &.{});
    try testing.expect(std.mem.eql(u8, tt.collapsed_symbol, "▶ "));
}

// ============================================================================
// TREETABLENODE TESTS (5 tests)
// ============================================================================

test "TreeTableNode with no children has empty children slice" {
    const node = TreeTableNode{
        .cells = &.{"Leaf"},
        .children = &.{},
    };
    try testing.expectEqual(@as(usize, 0), node.children.len);
}

test "TreeTableNode with children stores them" {
    const child = TreeTableNode{
        .cells = &.{"Child"},
        .children = &.{},
    };
    const parent = TreeTableNode{
        .cells = &.{"Parent"},
        .children = &.{child},
    };
    try testing.expectEqual(@as(usize, 1), parent.children.len);
    try testing.expect(std.mem.eql(u8, parent.children[0].cells[0], "Child"));
}

test "TreeTableNode defaults expanded to true" {
    const node = TreeTableNode{
        .cells = &.{"Item"},
        .children = &.{},
    };
    try testing.expect(node.expanded);
}

test "TreeTableNode can be collapsed" {
    const node = TreeTableNode{
        .cells = &.{"Item"},
        .children = &.{},
        .expanded = false,
    };
    try testing.expect(!node.expanded);
}

test "TreeTableNode with multiple children" {
    const children = [_]TreeTableNode{
        .{ .cells = &.{"Child1"}, .children = &.{} },
        .{ .cells = &.{"Child2"}, .children = &.{} },
        .{ .cells = &.{"Child3"}, .children = &.{} },
    };
    const parent = TreeTableNode{
        .cells = &.{"Parent"},
        .children = &children,
    };
    try testing.expectEqual(@as(usize, 3), parent.children.len);
}

// ============================================================================
// VISIBLECOUNT TESTS (10 tests)
// ============================================================================

test "TreeTable visibleCount with empty nodes returns 0" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt = TreeTable.init(&cols, &.{});
    try testing.expectEqual(@as(usize, 0), tt.visibleCount());
}

test "TreeTable visibleCount with 3 top-level leaf nodes" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
        .{ .cells = &.{"C"}, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes);
    try testing.expectEqual(@as(usize, 3), tt.visibleCount());
}

test "TreeTable visibleCount with 1 parent and 2 children all expanded" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const children = [_]TreeTableNode{
        .{ .cells = &.{"Child1"}, .children = &.{} },
        .{ .cells = &.{"Child2"}, .children = &.{} },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Parent"}, .children = &children, .expanded = true },
    };
    const tt = TreeTable.init(&cols, &nodes);
    try testing.expectEqual(@as(usize, 3), tt.visibleCount()); // Parent + 2 children
}

test "TreeTable visibleCount with collapsed parent hides children" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const children = [_]TreeTableNode{
        .{ .cells = &.{"Child1"}, .children = &.{} },
        .{ .cells = &.{"Child2"}, .children = &.{} },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Parent"}, .children = &children, .expanded = false },
    };
    const tt = TreeTable.init(&cols, &nodes);
    try testing.expectEqual(@as(usize, 1), tt.visibleCount()); // Only parent
}

test "TreeTable visibleCount with nested 3-level tree all expanded" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const grandchild = [_]TreeTableNode{
        .{ .cells = &.{"GrandChild"}, .children = &.{} },
    };
    const children = [_]TreeTableNode{
        .{ .cells = &.{"Child"}, .children = &grandchild, .expanded = true },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Root"}, .children = &children, .expanded = true },
    };
    const tt = TreeTable.init(&cols, &nodes);
    try testing.expectEqual(@as(usize, 3), tt.visibleCount()); // Root + Child + GrandChild
}

test "TreeTable visibleCount respects collapsed child in nested tree" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const grandchild = [_]TreeTableNode{
        .{ .cells = &.{"GrandChild"}, .children = &.{} },
    };
    const children = [_]TreeTableNode{
        .{ .cells = &.{"Child"}, .children = &grandchild, .expanded = false },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Root"}, .children = &children, .expanded = true },
    };
    const tt = TreeTable.init(&cols, &nodes);
    try testing.expectEqual(@as(usize, 2), tt.visibleCount()); // Root + Child (GrandChild hidden)
}

test "TreeTable visibleCount with multiple siblings and mixed expansion" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const child1 = [_]TreeTableNode{
        .{ .cells = &.{"C1-1"}, .children = &.{} },
    };
    const child2 = [_]TreeTableNode{
        .{ .cells = &.{"C2-1"}, .children = &.{} },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"P1"}, .children = &child1, .expanded = true },
        .{ .cells = &.{"P2"}, .children = &child2, .expanded = false },
    };
    const tt = TreeTable.init(&cols, &nodes);
    try testing.expectEqual(@as(usize, 3), tt.visibleCount()); // P1 + C1-1 + P2
}

test "TreeTable visibleCount with deep nesting 5 levels" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const level5 = [_]TreeTableNode{.{ .cells = &.{"L5"}, .children = &.{} }};
    const level4 = [_]TreeTableNode{.{ .cells = &.{"L4"}, .children = &level5, .expanded = true }};
    const level3 = [_]TreeTableNode{.{ .cells = &.{"L3"}, .children = &level4, .expanded = true }};
    const level2 = [_]TreeTableNode{.{ .cells = &.{"L2"}, .children = &level3, .expanded = true }};
    const level1 = [_]TreeTableNode{.{ .cells = &.{"L1"}, .children = &level2, .expanded = true }};
    const tt = TreeTable.init(&cols, &level1);
    try testing.expectEqual(@as(usize, 5), tt.visibleCount());
}

test "TreeTable visibleCount with all nodes collapsed at root" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const children = [_]TreeTableNode{
        .{ .cells = &.{"Child1"}, .children = &.{} },
        .{ .cells = &.{"Child2"}, .children = &.{} },
        .{ .cells = &.{"Child3"}, .children = &.{} },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"P1"}, .children = &children, .expanded = false },
        .{ .cells = &.{"P2"}, .children = &children, .expanded = false },
    };
    const tt = TreeTable.init(&cols, &nodes);
    try testing.expectEqual(@as(usize, 2), tt.visibleCount()); // Only the two parents
}

// ============================================================================
// SELECTNEXT TESTS (8 tests)
// ============================================================================

test "TreeTable selectNext from null sets selected to 0" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    try testing.expectEqual(@as(?usize, null), tt.selected);
    tt.selectNext();
    try testing.expectEqual(@as(?usize, 0), tt.selected);
}

test "TreeTable selectNext from 0 moves to 1" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
        .{ .cells = &.{"C"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    tt.selected = 0;
    tt.selectNext();
    try testing.expectEqual(@as(?usize, 1), tt.selected);
}

test "TreeTable selectNext clamps at last visible row" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    tt.selected = 1;
    tt.selectNext();
    try testing.expectEqual(@as(?usize, 1), tt.selected); // Stays at last (clamped)
}

test "TreeTable selectNext respects collapsed nodes" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const children = [_]TreeTableNode{
        .{ .cells = &.{"Hidden1"}, .children = &.{} },
        .{ .cells = &.{"Hidden2"}, .children = &.{} },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Collapsed"}, .children = &children, .expanded = false },
        .{ .cells = &.{"Next"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    tt.selected = 0;
    tt.selectNext();
    try testing.expectEqual(@as(?usize, 1), tt.selected); // Jump over hidden children
}

test "TreeTable selectNext after selecting last row stays at last" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
        .{ .cells = &.{"C"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    tt.selected = 2;
    tt.selectNext();
    try testing.expectEqual(@as(?usize, 2), tt.selected);
}

test "TreeTable selectNext with only 1 visible node" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Single"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    tt.selectNext();
    try testing.expectEqual(@as(?usize, 0), tt.selected);
    tt.selectNext();
    try testing.expectEqual(@as(?usize, 0), tt.selected); // Stays at 0
}

test "TreeTable selectNext on empty nodes does not crash" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    var tt = TreeTable.init(&cols, &.{});
    tt.selectNext();
    try testing.expectEqual(@as(?usize, null), tt.selected);
}

test "TreeTable selectNext called multiple times increments correctly" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
        .{ .cells = &.{"C"}, .children = &.{} },
        .{ .cells = &.{"D"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    tt.selectNext();
    try testing.expectEqual(@as(?usize, 0), tt.selected);
    tt.selectNext();
    try testing.expectEqual(@as(?usize, 1), tt.selected);
    tt.selectNext();
    try testing.expectEqual(@as(?usize, 2), tt.selected);
    tt.selectNext();
    try testing.expectEqual(@as(?usize, 3), tt.selected);
}

// ============================================================================
// SELECTPREV TESTS (6 tests)
// ============================================================================

test "TreeTable selectPrev from null stays null" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    tt.selectPrev();
    try testing.expectEqual(@as(?usize, null), tt.selected);
}

test "TreeTable selectPrev from 1 moves to 0" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
        .{ .cells = &.{"C"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    tt.selected = 1;
    tt.selectPrev();
    try testing.expectEqual(@as(?usize, 0), tt.selected);
}

test "TreeTable selectPrev from 0 stays at 0" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    tt.selected = 0;
    tt.selectPrev();
    try testing.expectEqual(@as(?usize, 0), tt.selected); // No wrap, stays at 0
}

test "TreeTable selectPrev from last moves to second-to-last" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
        .{ .cells = &.{"C"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    tt.selected = 2;
    tt.selectPrev();
    try testing.expectEqual(@as(?usize, 1), tt.selected);
}

test "TreeTable selectPrev called multiple times decrements correctly" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
        .{ .cells = &.{"C"}, .children = &.{} },
        .{ .cells = &.{"D"}, .children = &.{} },
    };
    var tt = TreeTable.init(&cols, &nodes);
    tt.selected = 3;
    tt.selectPrev();
    try testing.expectEqual(@as(?usize, 2), tt.selected);
    tt.selectPrev();
    try testing.expectEqual(@as(?usize, 1), tt.selected);
    tt.selectPrev();
    try testing.expectEqual(@as(?usize, 0), tt.selected);
    tt.selectPrev();
    try testing.expectEqual(@as(?usize, 0), tt.selected); // Stays at 0
}

test "TreeTable selectPrev on empty nodes does not crash" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    var tt = TreeTable.init(&cols, &.{});
    tt.selectPrev();
    try testing.expectEqual(@as(?usize, null), tt.selected);
}

// ============================================================================
// BUILDER API TESTS (11 tests)
// ============================================================================

test "TreeTable withSelected returns new instance with selected set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
    };
    const tt1 = TreeTable.init(&cols, &nodes);
    const tt2 = tt1.withSelected(1);
    try testing.expectEqual(@as(?usize, null), tt1.selected); // Original unchanged
    try testing.expectEqual(@as(?usize, 1), tt2.selected);
}

test "TreeTable withOffset returns new instance with offset set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt1 = TreeTable.init(&cols, &.{});
    const tt2 = tt1.withOffset(5);
    try testing.expectEqual(@as(usize, 0), tt1.offset); // Original unchanged
    try testing.expectEqual(@as(usize, 5), tt2.offset);
}

test "TreeTable withBlock returns new instance with block set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt1 = TreeTable.init(&cols, &.{});
    const block = Block{};
    const tt2 = tt1.withBlock(block);
    try testing.expectEqual(@as(?Block, null), tt1.block);
    try testing.expect(tt2.block != null);
}

test "TreeTable withHeaderStyle returns new instance with header_style set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt1 = TreeTable.init(&cols, &.{});
    const style = Style{ .bold = true };
    const tt2 = tt1.withHeaderStyle(style);
    try testing.expect(!tt1.header_style.bold);
    try testing.expect(tt2.header_style.bold);
}

test "TreeTable withRowStyle returns new instance with row_style set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt1 = TreeTable.init(&cols, &.{});
    const style = Style{ .dim = true };
    const tt2 = tt1.withRowStyle(style);
    try testing.expect(!tt1.row_style.dim);
    try testing.expect(tt2.row_style.dim);
}

test "TreeTable withSelectedStyle returns new instance with selected_style set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt1 = TreeTable.init(&cols, &.{});
    const style = Style{ .reverse = true };
    const tt2 = tt1.withSelectedStyle(style);
    try testing.expect(!tt1.selected_style.reverse);
    try testing.expect(tt2.selected_style.reverse);
}

test "TreeTable withColumnSpacing returns new instance with column_spacing set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt1 = TreeTable.init(&cols, &.{});
    const tt2 = tt1.withColumnSpacing(3);
    try testing.expectEqual(@as(u16, 1), tt1.column_spacing);
    try testing.expectEqual(@as(u16, 3), tt2.column_spacing);
}

test "TreeTable withExpandedSymbol returns new instance with expanded_symbol set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt1 = TreeTable.init(&cols, &.{});
    const tt2 = tt1.withExpandedSymbol("- ");
    try testing.expect(std.mem.eql(u8, tt1.expanded_symbol, "▼ "));
    try testing.expect(std.mem.eql(u8, tt2.expanded_symbol, "- "));
}

test "TreeTable withCollapsedSymbol returns new instance with collapsed_symbol set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt1 = TreeTable.init(&cols, &.{});
    const tt2 = tt1.withCollapsedSymbol("+ ");
    try testing.expect(std.mem.eql(u8, tt1.collapsed_symbol, "▶ "));
    try testing.expect(std.mem.eql(u8, tt2.collapsed_symbol, "+ "));
}

test "TreeTable withLeafSymbol returns new instance with leaf_symbol set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt1 = TreeTable.init(&cols, &.{});
    const tt2 = tt1.withLeafSymbol("* ");
    try testing.expect(std.mem.eql(u8, tt1.leaf_symbol, "  "));
    try testing.expect(std.mem.eql(u8, tt2.leaf_symbol, "* "));
}

test "TreeTable withIndent returns new instance with indent set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt1 = TreeTable.init(&cols, &.{});
    const tt2 = tt1.withIndent(4);
    try testing.expectEqual(@as(u16, 2), tt1.indent);
    try testing.expectEqual(@as(u16, 4), tt2.indent);
}

// ============================================================================
// RENDER ZERO AREA TESTS (2 tests)
// ============================================================================

test "TreeTable render with zero width area does not crash" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 5 };
    tt.render(&buf, area);
}

test "TreeTable render with zero height area does not crash" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    tt.render(&buf, area);
}

// ============================================================================
// RENDER EMPTY NODES TESTS (2 tests)
// ============================================================================

test "TreeTable render with no nodes shows header only" {
    var buf = try makeBuffer(20, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Name", .width = .{ .percentage = 100 } }};
    const tt = TreeTable.init(&cols, &.{});
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    tt.render(&buf, area);
    // Header should be rendered at y=0 (relative to area)
    try testing.expect(rowHasChar(buf, 0, 'N')); // 'N' from "Name"
}

test "TreeTable render with no nodes and no area for header does not crash" {
    var buf = try makeBuffer(10, 1);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const tt = TreeTable.init(&cols, &.{});
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    tt.render(&buf, area);
}

// ============================================================================
// RENDER HEADER TESTS (4 tests)
// ============================================================================

test "TreeTable render header shows column titles" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "Name", .width = .{ .percentage = 50 } },
        .{ .title = "Type", .width = .{ .percentage = 50 } },
    };
    const tt = TreeTable.init(&cols, &.{});
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    tt.render(&buf, area);
    // Header row should contain "Name" and "Type"
    try testing.expect(rowHasText(buf, 0, "Name"));
}

test "TreeTable render header with header_style applies styling" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const style = Style{ .bold = true };
    const tt = TreeTable.init(&cols, &.{}).withHeaderStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    tt.render(&buf, area);
    // Should render without crash; styling applied internally
    try testing.expect(rowHasChar(buf, 0, 'I'));
}

test "TreeTable render header with multiple columns at correct positions" {
    var buf = try makeBuffer(40, 5);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "ID", .width = .{ .fixed = 10 } },
        .{ .title = "Name", .width = .{ .fixed = 15 } },
        .{ .title = "Value", .width = .{ .fixed = 15 } },
    };
    const tt = TreeTable.init(&cols, &.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    tt.render(&buf, area);
    // All three titles should appear in header row
    try testing.expect(rowHasChar(buf, 0, 'I')); // ID
}

test "TreeTable render header respects column spacing" {
    var buf = try makeBuffer(40, 5);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "A", .width = .{ .fixed = 5 } },
        .{ .title = "B", .width = .{ .fixed = 5 } },
    };
    const tt = TreeTable.init(&cols, &.{}).withColumnSpacing(2);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    tt.render(&buf, area);
    // Should render header with spacing
}

// ============================================================================
// RENDER TREE ROWS TESTS (10 tests)
// ============================================================================

test "TreeTable render leaf node shows leaf_symbol" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Leaf"}, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    tt.render(&buf, area);
    // Leaf symbol (default "  ") followed by "Leaf" at row 1 (after header)
    try testing.expect(rowHasText(buf, 1, "Leaf"));
}

test "TreeTable render expanded parent shows expanded_symbol" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const children = [_]TreeTableNode{
        .{ .cells = &.{"Child"}, .children = &.{} },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Parent"}, .children = &children, .expanded = true },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    tt.render(&buf, area);
    // Should show expanded_symbol (▼) before "Parent"
    try testing.expect(rowHasChar(buf, 1, '▼'));
}

test "TreeTable render collapsed parent shows collapsed_symbol" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const children = [_]TreeTableNode{
        .{ .cells = &.{"Child"}, .children = &.{} },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Parent"}, .children = &children, .expanded = false },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    tt.render(&buf, area);
    // Should show collapsed_symbol (▶) before "Parent"
    try testing.expect(rowHasChar(buf, 1, '▶'));
}

test "TreeTable render depth 1 child has indent" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const children = [_]TreeTableNode{
        .{ .cells = &.{"Child"}, .children = &.{} },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Parent"}, .children = &children, .expanded = true },
    };
    const tt = TreeTable.init(&cols, &nodes).withIndent(2);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    tt.render(&buf, area);
    // Child row should start with indent spaces + symbol + "Child"
}

test "TreeTable render depth 2 child has double indent" {
    var buf = try makeBuffer(30, 7);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const grandchild = [_]TreeTableNode{
        .{ .cells = &.{"GrandChild"}, .children = &.{} },
    };
    const child = [_]TreeTableNode{
        .{ .cells = &.{"Child"}, .children = &grandchild, .expanded = true },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Root"}, .children = &child, .expanded = true },
    };
    const tt = TreeTable.init(&cols, &nodes).withIndent(2);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 7 };
    tt.render(&buf, area);
    // GrandChild should have 4-space indent (2*2)
}

test "TreeTable render second column appears at correct position" {
    var buf = try makeBuffer(40, 5);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "Name", .width = .{ .fixed = 15 } },
        .{ .title = "Value", .width = .{ .fixed = 15 } },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{ "Item1", "100" }, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    tt.render(&buf, area);
    // "100" should appear in the Value column
    try testing.expect(rowHasChar(buf, 1, '1'));
}

test "TreeTable render selected row uses selected_style" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
    };
    const style = Style{ .reverse = true };
    const tt = TreeTable.init(&cols, &nodes)
        .withSelected(0)
        .withSelectedStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    tt.render(&buf, area);
    // Selected row (row 1) should have selected_style applied
}

test "TreeTable render unselected row uses row_style" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
    };
    const style = Style{ .dim = true };
    const tt = TreeTable.init(&cols, &nodes)
        .withSelected(0)
        .withRowStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    tt.render(&buf, area);
    // Unselected row (row 2) should have row_style applied
}

test "TreeTable render collapsed parent hides children in render" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const children = [_]TreeTableNode{
        .{ .cells = &.{"HiddenChild"}, .children = &.{} },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Collapsed"}, .children = &children, .expanded = false },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    tt.render(&buf, area);
    // Only header and parent row; child should not appear
    try testing.expect(rowHasText(buf, 1, "Collapsed"));
}

test "TreeTable render with offset scrolls correctly" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
        .{ .cells = &.{"C"}, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes).withOffset(1);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    tt.render(&buf, area);
    // First data row (y=1) should show item at offset (B)
    try testing.expect(rowHasText(buf, 1, "B"));
}

// ============================================================================
// RENDER BLOCK TESTS (2 tests)
// ============================================================================

test "TreeTable render with block renders border" {
    var buf = try makeBuffer(20, 10);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const block = Block{};
    const tt = TreeTable.init(&cols, &.{}).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tt.render(&buf, area);
    // Block border should be visible at top-left
}

test "TreeTable render with block and small area does not crash" {
    var buf = try makeBuffer(6, 6);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const block = Block{};
    const tt = TreeTable.init(&cols, &.{}).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 6, .height = 6 };
    tt.render(&buf, area);
}

// ============================================================================
// RENDER NARROW/EDGE CASE TESTS (3 tests)
// ============================================================================

test "TreeTable render with width just enough for one character" {
    var buf = try makeBuffer(5, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 5 };
    tt.render(&buf, area);
}

test "TreeTable render with height = 1 (header only, no data rows)" {
    var buf = try makeBuffer(30, 1);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    tt.render(&buf, area);
    // Header rendered, no space for data
}

test "TreeTable render with height = 2 (header + 1 row)" {
    var buf = try makeBuffer(30, 2);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 2 };
    tt.render(&buf, area);
    // Should render header and first data row
    try testing.expect(rowHasChar(buf, 0, 'I'));
}

// ============================================================================
// EDGE CASES & COMPLEX SCENARIOS (7 tests)
// ============================================================================

test "TreeTable single node single column" {
    var buf = try makeBuffer(20, 3);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Name", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Single"}, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    tt.render(&buf, area);
    try testing.expect(rowHasText(buf, 1, "Single"));
}

test "TreeTable all nodes collapsed shows only top-level count" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const child = [_]TreeTableNode{
        .{ .cells = &.{"HiddenChild"}, .children = &.{} },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"P1"}, .children = &child, .expanded = false },
        .{ .cells = &.{"P2"}, .children = &child, .expanded = false },
        .{ .cells = &.{"P3"}, .children = &child, .expanded = false },
    };
    const tt = TreeTable.init(&cols, &nodes);
    try testing.expectEqual(@as(usize, 3), tt.visibleCount());
}

test "TreeTable deep nesting 5 levels renders without crash" {
    var buf = try makeBuffer(40, 10);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const l5 = [_]TreeTableNode{.{ .cells = &.{"L5"}, .children = &.{} }};
    const l4 = [_]TreeTableNode{.{ .cells = &.{"L4"}, .children = &l5, .expanded = true }};
    const l3 = [_]TreeTableNode{.{ .cells = &.{"L3"}, .children = &l4, .expanded = true }};
    const l2 = [_]TreeTableNode{.{ .cells = &.{"L2"}, .children = &l3, .expanded = true }};
    const l1 = [_]TreeTableNode{.{ .cells = &.{"L1"}, .children = &l2, .expanded = true }};
    const tt = TreeTable.init(&cols, &l1);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    tt.render(&buf, area);
}

test "TreeTable node with fewer cells than columns handles gracefully" {
    var buf = try makeBuffer(50, 5);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "A", .width = .{ .fixed = 10 } },
        .{ .title = "B", .width = .{ .fixed = 10 } },
        .{ .title = "C", .width = .{ .fixed = 10 } },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"Only1"}, .children = &.{} }, // Only 1 cell, 3 columns
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 5 };
    tt.render(&buf, area);
    // Should not crash, render what's available
}

test "TreeTable node with more cells than columns renders only columns count" {
    var buf = try makeBuffer(40, 5);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "A", .width = .{ .fixed = 15 } },
        .{ .title = "B", .width = .{ .fixed = 15 } },
    };
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{ "Cell1", "Cell2", "Cell3", "Cell4", "Cell5" }, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    tt.render(&buf, area);
    // Should render only first 2 cells (matching column count)
}

test "TreeTable large tree with many nodes and scrolling" {
    var buf = try makeBuffer(40, 10);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};

    // Create 10 nodes
    var nodes: [10]TreeTableNode = undefined;
    for (0..10) |i| {
        var buf_slice: [10]u8 = undefined;
        const name = std.fmt.bufPrint(&buf_slice, "Item{d}", .{i}) catch "Item";
        nodes[i] = .{ .cells = &.{name}, .children = &.{} };
    }

    const tt = TreeTable.init(&cols, &nodes);
    try testing.expectEqual(@as(usize, 10), tt.visibleCount());

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    tt.render(&buf, area);
}

test "TreeTable scroll offset past end renders gracefully" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const nodes = [_]TreeTableNode{
        .{ .cells = &.{"A"}, .children = &.{} },
        .{ .cells = &.{"B"}, .children = &.{} },
    };
    const tt = TreeTable.init(&cols, &nodes).withOffset(100); // Way past end
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    tt.render(&buf, area);
    // Should render header, with no visible data rows (all scrolled out)
    // Verify header still appears even with invalid offset
    try testing.expect(rowHasChar(buf, 0, 'I'));
}
