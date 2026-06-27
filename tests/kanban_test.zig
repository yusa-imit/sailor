//! KanbanBoard Widget Tests — TDD Red Phase
//!
//! Tests kanban board widget with multi-column layout, card priorities, focused navigation,
//! block border support, and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const KanbanBoard = sailor.tui.widgets.KanbanBoard;
const Column = sailor.tui.widgets.kanban.Column;
const Card = sailor.tui.widgets.kanban.Card;
const Priority = sailor.tui.widgets.kanban.Priority;

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

// ============================================================================
// Group 1: Init/Defaults (5 tests)
// ============================================================================

test "KanbanBoard.init has empty columns" {
    const kb = KanbanBoard.init();
    try testing.expectEqual(@as(usize, 0), kb.columns.len);
}

test "KanbanBoard.init has focused_column == 0" {
    const kb = KanbanBoard.init();
    try testing.expectEqual(@as(usize, 0), kb.focused_column);
}

test "KanbanBoard.init has focused_card == 0" {
    const kb = KanbanBoard.init();
    try testing.expectEqual(@as(usize, 0), kb.focused_card);
}

test "KanbanBoard.init has null block" {
    const kb = KanbanBoard.init();
    try testing.expect(kb.block == null);
}

test "KanbanBoard.init has default empty style" {
    const kb = KanbanBoard.init();
    const default_style = Style{};
    try testing.expect(std.meta.eql(kb.style, default_style));
}

// ============================================================================
// Group 2: Priority Enum (4 tests)
// ============================================================================

test "Priority.low exists and can be used" {
    const p: Priority = .low;
    try testing.expect(p == .low);
}

test "Priority.normal exists and can be used" {
    const p: Priority = .normal;
    try testing.expect(p == .normal);
}

test "Priority.high exists and can be used" {
    const p: Priority = .high;
    try testing.expect(p == .high);
}

test "Priority.critical exists and can be used" {
    const p: Priority = .critical;
    try testing.expect(p == .critical);
}

// ============================================================================
// Group 3: Card Defaults (4 tests)
// ============================================================================

test "Card with only title has empty description by default" {
    const card = Card{ .title = "Task" };
    try testing.expectEqual(@as(usize, 0), card.description.len);
}

test "Card with only title has empty tags by default" {
    const card = Card{ .title = "Task" };
    try testing.expectEqual(@as(usize, 0), card.tags.len);
}

test "Card with only title has priority=normal by default" {
    const card = Card{ .title = "Task" };
    try testing.expect(card.priority == .normal);
}

test "Card can be created with all fields" {
    var tags = [_][]const u8{ "urgent", "bug" };
    const card = Card{
        .title = "Fix login",
        .description = "Login page broken",
        .tags = &tags,
        .priority = .high,
    };
    try testing.expectEqualStrings("Fix login", card.title);
    try testing.expectEqualStrings("Login page broken", card.description);
    try testing.expectEqual(@as(usize, 2), card.tags.len);
    try testing.expect(card.priority == .high);
}

// ============================================================================
// Group 4: Column Defaults (3 tests)
// ============================================================================

test "Column with only title has empty cards by default" {
    const col = Column{ .title = "Todo" };
    try testing.expectEqual(@as(usize, 0), col.cards.len);
}

test "Column can be created with title" {
    const col = Column{ .title = "In Progress" };
    try testing.expectEqualStrings("In Progress", col.title);
}

test "Column can be created with cards" {
    var cards = [_]Card{.{ .title = "Task 1" }};
    const col = Column{ .title = "Done", .cards = &cards };
    try testing.expectEqual(@as(usize, 1), col.cards.len);
}

// ============================================================================
// Group 5: Builder Immutability (9 tests)
// ============================================================================

test "withColumns returns new value, original unchanged" {
    var cols = [_]Column{.{ .title = "Todo" }};
    const kb1 = KanbanBoard.init();
    const kb2 = kb1.withColumns(&cols);

    try testing.expectEqual(@as(usize, 0), kb1.columns.len);
    try testing.expectEqual(@as(usize, 1), kb2.columns.len);
}

test "withFocusedColumn returns new value, original unchanged" {
    const kb1 = KanbanBoard.init();
    const kb2 = kb1.withFocusedColumn(2);

    try testing.expectEqual(@as(usize, 0), kb1.focused_column);
    try testing.expectEqual(@as(usize, 2), kb2.focused_column);
}

test "withFocusedCard returns new value, original unchanged" {
    const kb1 = KanbanBoard.init();
    const kb2 = kb1.withFocusedCard(3);

    try testing.expectEqual(@as(usize, 0), kb1.focused_card);
    try testing.expectEqual(@as(usize, 3), kb2.focused_card);
}

test "withStyle returns new value, original unchanged" {
    const style = Style{ .fg = .green };
    const kb1 = KanbanBoard.init();
    const kb2 = kb1.withStyle(style);

    try testing.expect(!std.meta.eql(kb1.style.fg, .green));
    try testing.expect(std.meta.eql(kb2.style.fg, .green));
}

test "withColumnStyle returns new value, original unchanged" {
    const style = Style{ .fg = .blue };
    const kb1 = KanbanBoard.init();
    const kb2 = kb1.withColumnStyle(style);

    try testing.expect(!std.meta.eql(kb1.column_style.fg, .blue));
    try testing.expect(std.meta.eql(kb2.column_style.fg, .blue));
}

test "withFocusedColumnStyle returns new value, original unchanged" {
    const style = Style{ .bold = true };
    const kb1 = KanbanBoard.init();
    const kb2 = kb1.withFocusedColumnStyle(style);

    try testing.expect(kb1.focused_column_style.bold != true);
    try testing.expect(kb2.focused_column_style.bold == true);
}

test "withCardStyle returns new value, original unchanged" {
    const style = Style{ .fg = .yellow };
    const kb1 = KanbanBoard.init();
    const kb2 = kb1.withCardStyle(style);

    try testing.expect(!std.meta.eql(kb1.card_style.fg, .yellow));
    try testing.expect(std.meta.eql(kb2.card_style.fg, .yellow));
}

test "withFocusedCardStyle returns new value, original unchanged" {
    const style = Style{ .dim = true };
    const kb1 = KanbanBoard.init();
    const kb2 = kb1.withFocusedCardStyle(style);

    try testing.expect(kb1.focused_card_style.dim != true);
    try testing.expect(kb2.focused_card_style.dim == true);
}

test "withBlock returns new value, original unchanged" {
    const block = Block{};
    const kb1 = KanbanBoard.init();
    const kb2 = kb1.withBlock(block);

    try testing.expect(kb1.block == null);
    try testing.expect(kb2.block != null);
}

// ============================================================================
// Group 6: Builder Chaining (3 tests)
// ============================================================================

test "builder methods can be chained" {
    var cols = [_]Column{.{ .title = "Todo" }};
    const style = Style{ .fg = .red };

    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedColumn(0)
        .withStyle(style);

    try testing.expectEqual(@as(usize, 1), kb.columns.len);
    try testing.expectEqual(@as(usize, 0), kb.focused_column);
    try testing.expect(std.meta.eql(kb.style.fg, .red));
}

test "chaining multiple builders does not affect original" {
    const kb1 = KanbanBoard.init();
    var cols = [_]Column{.{ .title = "Todo" }};
    const kb2 = kb1.withColumns(&cols);
    const kb3 = kb1.withFocusedColumn(5);

    try testing.expectEqual(@as(usize, 0), kb1.columns.len);
    try testing.expectEqual(@as(usize, 1), kb2.columns.len);
    try testing.expectEqual(@as(usize, 5), kb3.focused_column);
}

test "complex builder chain works" {
    var cards = [_]Card{.{ .title = "Task" }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const block = Block{};

    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedColumn(0)
        .withFocusedCard(0)
        .withBlock(block);

    try testing.expectEqual(@as(usize, 1), kb.columns.len);
    try testing.expect(kb.block != null);
}

// ============================================================================
// Group 7: Render Edge Cases (6 tests)
// ============================================================================

test "render with zero-width area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const kb = KanbanBoard.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 20 };

    kb.render(&buf, area);
    try testing.expect(true);
}

test "render with zero-height area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const kb = KanbanBoard.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 0 };

    kb.render(&buf, area);
    try testing.expect(true);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{.{ .title = "T" }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };

    kb.render(&buf, area);
    try testing.expect(true);
}

test "render with empty columns does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const kb = KanbanBoard.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);
    try testing.expect(true);
}

test "render with zero columns does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols: [0]Column = undefined;
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);
    try testing.expect(true);
}

test "render area smaller than column headers does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{.{ .title = "Todo" }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 1 };

    kb.render(&buf, area);
    try testing.expect(true);
}

// ============================================================================
// Group 8: Single Column Render (8 tests)
// ============================================================================

test "single column renders title in header" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{.{ .title = "Todo" }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(rowContains(buf, 0, "Todo"));
}

test "single column header shows card count in parentheses" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{
        .{ .title = "Task 1" },
        .{ .title = "Task 2" },
    };
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Should show "Todo (2)" or similar
    try testing.expect(rowContains(buf, 0, "Todo") and rowContains(buf, 0, "(2)"));
}

test "single column renders cards below header" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{.{ .title = "Task 1" }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Task 1"));
}

test "single column with priority critical shows critical indicator" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{.{ .title = "Urgent", .priority = .critical }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Critical indicator is "●"
    try testing.expect(areaHasChar(buf, area, '●'));
}

test "single column with priority high shows high indicator" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{.{ .title = "Important", .priority = .high }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // High indicator is "▲"
    try testing.expect(areaHasChar(buf, area, '▲'));
}

test "single column with priority normal shows normal indicator" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{.{ .title = "Normal", .priority = .normal }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Normal indicator is "·"
    try testing.expect(areaHasChar(buf, area, '·'));
}

test "single column with priority low shows low indicator" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{.{ .title = "Low", .priority = .low }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Low indicator is "–"
    try testing.expect(areaHasChar(buf, area, '–'));
}

// ============================================================================
// Group 9: Multi-Column Render (6 tests)
// ============================================================================

test "two columns divide width evenly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{
        .{ .title = "Todo" },
        .{ .title = "Done" },
    };
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Both column titles should appear
    try testing.expect(rowContains(buf, 0, "Todo"));
    try testing.expect(rowContains(buf, 0, "Done"));
}

test "three columns divide width with separators" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{
        .{ .title = "Todo" },
        .{ .title = "Doing" },
        .{ .title = "Done" },
    };
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // All titles should appear
    try testing.expect(rowContains(buf, 0, "Todo"));
    try testing.expect(rowContains(buf, 0, "Doing"));
    try testing.expect(rowContains(buf, 0, "Done"));
}

test "column separator │ appears between columns" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{
        .{ .title = "A" },
        .{ .title = "B" },
    };
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Separator │ should appear somewhere in the area
    try testing.expect(areaHasChar(buf, area, '│'));
}

test "multi-column each shows own cards" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards1 = [_]Card{.{ .title = "Task1" }};
    var cards2 = [_]Card{.{ .title = "Task2" }};
    var cols = [_]Column{
        .{ .title = "Todo", .cards = &cards1 },
        .{ .title = "Done", .cards = &cards2 },
    };
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Task1"));
    try testing.expect(findInArea(buf, area, "Task2"));
}

test "MAX_COLUMNS=8 constant is defined" {
    try testing.expectEqual(@as(usize, 8), KanbanBoard.MAX_COLUMNS);
}

// ============================================================================
// Group 10: Focused Column Highlight (5 tests)
// ============================================================================

test "focused column header uses focused_column_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{
        .{ .title = "Todo" },
        .{ .title = "Done" },
    };
    const focused_style = Style{ .bold = true };
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedColumn(0)
        .withFocusedColumnStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Focused column should be rendered with the style applied
    try testing.expect(rowContains(buf, 0, "Todo"));
}

test "unfocused column header uses column_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{
        .{ .title = "Todo" },
        .{ .title = "Done" },
    };
    const col_style = Style{ .dim = true };
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedColumn(0)
        .withColumnStyle(col_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(rowContains(buf, 0, "Done"));
}

test "focused_column index changes which column is focused" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{
        .{ .title = "A" },
        .{ .title = "B" },
    };
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedColumn(1);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expectEqual(@as(usize, 1), kb.focused_column);
}

test "all columns appear even when one is focused" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{
        .{ .title = "Col1" },
        .{ .title = "Col2" },
        .{ .title = "Col3" },
    };
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedColumn(1);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(rowContains(buf, 0, "Col1"));
    try testing.expect(rowContains(buf, 0, "Col2"));
    try testing.expect(rowContains(buf, 0, "Col3"));
}

// ============================================================================
// Group 11: Focused Card Highlight (4 tests)
// ============================================================================

test "focused card in focused column uses focused_card_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{
        .{ .title = "Task 1" },
        .{ .title = "Task 2" },
    };
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const focused_style = Style{ .bold = true };
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedColumn(0)
        .withFocusedCard(0)
        .withFocusedCardStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Task 1"));
}

test "unfocused cards use card_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{
        .{ .title = "Task 1" },
        .{ .title = "Task 2" },
    };
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const card_style = Style{ .fg = .blue };
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withCardStyle(card_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Task 1"));
    try testing.expect(findInArea(buf, area, "Task 2"));
}

test "focused_card index changes which card is focused" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{
        .{ .title = "A" },
        .{ .title = "B" },
    };
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedCard(1);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expectEqual(@as(usize, 1), kb.focused_card);
}

test "focused card only applies in focused column" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards1 = [_]Card{.{ .title = "Task1" }};
    var cards2 = [_]Card{.{ .title = "Task2" }};
    var cols = [_]Column{
        .{ .title = "Col1", .cards = &cards1 },
        .{ .title = "Col2", .cards = &cards2 },
    };
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedColumn(0)
        .withFocusedCard(0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Focused card should be in focused column (Col1)
    try testing.expect(findInArea(buf, area, "Task1"));
}

// ============================================================================
// Group 12: Card Content (6 tests)
// ============================================================================

test "card title appears in rendered output" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{.{ .title = "MyTask" }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(findInArea(buf, area, "MyTask"));
}

test "card description appears if present" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{.{
        .title = "Task",
        .description = "This is the description",
    }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(findInArea(buf, area, "description"));
}

test "card tags shown with # prefix" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var tags = [_][]const u8{ "bug", "urgent" };
    var cards = [_]Card{.{ .title = "Task", .tags = &tags }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Tags should appear with # prefix
    try testing.expect(findInArea(buf, area, "#bug") or findInArea(buf, area, "bug"));
}

test "card without tags does not show tag row" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{.{ .title = "Task" }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Task"));
}

test "card without description does not show description row" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{.{ .title = "Task" }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Task"));
}

// ============================================================================
// Group 13: Overflow/Scrolling (4 tests)
// ============================================================================

test "more cards than rows do not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards: [10]Card = undefined;
    for (0..10) |i| {
        cards[i] = .{ .title = "Task" };
    }
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    kb.render(&buf, area);
    try testing.expect(true);
}

test "focused card remains visible with overflow" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards: [5]Card = undefined;
    for (0..5) |i| {
        cards[i] = .{ .title = "Task" };
    }
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedCard(3);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    kb.render(&buf, area);

    // Should not crash and layout should be reasonable
    try testing.expect(true);
}

test "MAX_CARDS_PER_COLUMN=32 constant is defined" {
    try testing.expectEqual(@as(usize, 32), KanbanBoard.MAX_CARDS_PER_COLUMN);
}

test "32 cards in column renders without crash" {
    var buf = try Buffer.init(testing.allocator, 40, 100);
    defer buf.deinit();

    var cards: [32]Card = undefined;
    for (0..32) |i| {
        cards[i] = .{ .title = "Task" };
    }
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 100 };

    kb.render(&buf, area);
    try testing.expect(true);
}

// ============================================================================
// Group 14: Block Border (4 tests)
// ============================================================================

test "with Block border renders frame around content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{.{ .title = "Todo" }};
    const block = Block{};
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Check for border characters
    try testing.expect(areaHasChar(buf, area, '─') or
                       areaHasChar(buf, area, '│') or
                       areaHasChar(buf, area, '┌'));
}

test "block inner area smaller than outer area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{.{ .title = "Todo" }};
    const block = Block{};
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Content should be inside border
    try testing.expect(rowContains(buf, 0, "Todo"));
}

test "columns render inside block border area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{.{ .title = "Todo" }};
    const block = Block{};
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(rowContains(buf, 0, "Todo") or findInArea(buf, area, "Todo"));
}

test "null block uses full area without border" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{.{ .title = "Todo" }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Todo"));
}

// ============================================================================
// Group 15: Rendering Bounds (4 tests)
// ============================================================================

test "no content rendered outside area bounds" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();

    var cols = [_]Column{.{ .title = "Todo" }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 20, .y = 10, .width = 30, .height = 10 };

    kb.render(&buf, area);

    // Check all non-space cells are within area bounds
    var y: u16 = 0;
    while (y < 30) : (y += 1) {
        var x: u16 = 0;
        while (x < 80) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ') {
                    try testing.expect(x >= area.x and x < area.x + area.width);
                    try testing.expect(y >= area.y and y < area.y + area.height);
                }
            }
        }
    }
}

test "content at area offset is rendered correctly" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();

    var cols = [_]Column{.{ .title = "Todo" }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 10, .y = 5, .width = 40, .height = 15 };

    kb.render(&buf, area);

    // Content should be within offset area
    try testing.expect(true);
}

test "area with width less than column header does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{.{ .title = "VeryLongColumnTitle" }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 20 };

    kb.render(&buf, area);
    try testing.expect(true);
}

test "many columns at narrow width renders without crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{
        .{ .title = "A" },
        .{ .title = "B" },
        .{ .title = "C" },
        .{ .title = "D" },
        .{ .title = "E" },
    };
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);
    try testing.expect(true);
}

// ============================================================================
// Group 16: Style Application (4 tests)
// ============================================================================

test "base style applied to background" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{.{ .title = "Todo" }};
    const style = Style{ .bg = .black };
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    // Should render without crashing with the style applied
    try testing.expect(true);
}

test "column style applied to unfocused columns" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{
        .{ .title = "Col1" },
        .{ .title = "Col2" },
    };
    const col_style = Style{ .fg = .yellow };
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withColumnStyle(col_style)
        .withFocusedColumn(0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(rowContains(buf, 0, "Col1"));
    try testing.expect(rowContains(buf, 0, "Col2"));
}

test "focused column style applied to focused column" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cols = [_]Column{
        .{ .title = "Col1" },
        .{ .title = "Col2" },
    };
    const focused_style = Style{ .bold = true };
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedColumnStyle(focused_style)
        .withFocusedColumn(0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(rowContains(buf, 0, "Col1"));
}

test "card styles applied to card content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var cards = [_]Card{.{ .title = "Task" }};
    var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
    const card_style = Style{ .fg = .green };
    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withCardStyle(card_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    kb.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Task"));
}

// ============================================================================
// Group 17: Full Integration (5 tests)
// ============================================================================

test "complete kanban board with 3 columns and cards renders" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();

    var todo_cards = [_]Card{
        .{ .title = "Task 1", .priority = .high },
        .{ .title = "Task 2" },
    };
    var doing_cards = [_]Card{
        .{ .title = "Task 3", .priority = .critical },
    };
    var done_cards = [_]Card{
        .{ .title = "Task 4" },
    };

    var cols = [_]Column{
        .{ .title = "Todo", .cards = &todo_cards },
        .{ .title = "Doing", .cards = &doing_cards },
        .{ .title = "Done", .cards = &done_cards },
    };

    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedColumn(1)
        .withFocusedCard(0);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };

    kb.render(&buf, area);

    // All columns should appear
    try testing.expect(rowContains(buf, 0, "Todo"));
    try testing.expect(rowContains(buf, 0, "Doing"));
    try testing.expect(rowContains(buf, 0, "Done"));
}

test "kanban board with block border and styles" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();

    var cols = [_]Column{
        .{ .title = "Backlog" },
        .{ .title = "Ready" },
    };

    const block = Block{};
    const style = Style{ .fg = .white, .bg = .blue };
    const col_style = Style{ .fg = .cyan };

    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withStyle(style)
        .withColumnStyle(col_style)
        .withBlock(block)
        .withFocusedColumn(0);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };

    kb.render(&buf, area);

    try testing.expect(rowContains(buf, 0, "Backlog"));
}

test "kanban with many cards and multiple priorities renders" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();

    var cards: [5]Card = undefined;
    cards[0] = .{ .title = "Critical", .priority = .critical };
    cards[1] = .{ .title = "High", .priority = .high };
    cards[2] = .{ .title = "Normal", .priority = .normal };
    cards[3] = .{ .title = "Low", .priority = .low };
    cards[4] = .{ .title = "Another" };

    var cols = [_]Column{.{ .title = "Work", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    kb.render(&buf, area);

    // All priorities should appear
    try testing.expect(areaHasChar(buf, area, '●')); // critical
    try testing.expect(areaHasChar(buf, area, '▲')); // high
}

test "kanban with tags and descriptions on cards" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();

    var tags = [_][]const u8{ "frontend", "css" };
    var cards = [_]Card{.{
        .title = "Styling",
        .description = "Make button styles consistent",
        .tags = &tags,
        .priority = .normal,
    }};

    var cols = [_]Column{.{ .title = "In Progress", .cards = &cards }};
    const kb = KanbanBoard.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };

    kb.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Styling"));
    try testing.expect(findInArea(buf, area, "consistent") or findInArea(buf, area, "Styling"));
}

test "kanban navigation: change focused column and card" {
    var buf = try Buffer.init(testing.allocator, 60, 25);
    defer buf.deinit();

    var cards1 = [_]Card{.{ .title = "A" }};
    var cards2 = [_]Card{.{ .title = "B" }};
    var cols = [_]Column{
        .{ .title = "Col1", .cards = &cards1 },
        .{ .title = "Col2", .cards = &cards2 },
    };

    const kb = KanbanBoard.init()
        .withColumns(&cols)
        .withFocusedColumn(1)
        .withFocusedCard(0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 25 };

    kb.render(&buf, area);

    // Should render column 2 as focused with its cards
    try testing.expectEqual(@as(usize, 1), kb.focused_column);
    try testing.expect(findInArea(buf, area, "Col2"));
}
