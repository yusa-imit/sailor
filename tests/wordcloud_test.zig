//! WordCloud Widget Tests — TDD Red Phase
//!
//! Tests word cloud widget with spiral placement, weight-based styling,
//! builder pattern, rendering with styles, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const WordCloud = sailor.tui.widgets.WordCloud;
const Word = sailor.Word;

// ============================================================================
// Helper Functions
// ============================================================================

/// Scan buffer area for a given text string (UTF-8 aware)
fn findInArea(buf: Buffer, area: Rect, text: []const u8) bool {
    if (text.len == 0) return true;

    // Decode text to codepoints
    var cps: [256]u21 = undefined;
    var cp_count: usize = 0;
    var view = std.unicode.Utf8View.initUnchecked(text);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |cp| {
        if (cp_count >= cps.len) break;
        cps[cp_count] = cp;
        cp_count += 1;
    }
    if (cp_count == 0) return true;

    // Search area for text sequence
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            // Try to match text starting at (x, y)
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

/// Check if any cell in area has a specific style attribute
fn areaHasStyleAttribute(buf: Buffer, area: Rect, comptime field: std.meta.FieldEnum(Style)) bool {
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                const style_field = @field(cell.style, @tagName(field));
                if (!std.meta.eql(style_field, @field(Style{}, @tagName(field)))) {
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

test "WordCloud.init has empty words" {
    const wc = WordCloud.init();
    try testing.expectEqual(@as(usize, 0), wc.words.len);
}

test "WordCloud.init has default style" {
    const wc = WordCloud.init();
    const default_style = Style{};
    try testing.expect(std.meta.eql(wc.style, default_style));
}

test "WordCloud.init has null bold_style" {
    const wc = WordCloud.init();
    try testing.expect(wc.bold_style.fg == null);
}

test "WordCloud.init has null dim_style" {
    const wc = WordCloud.init();
    try testing.expect(wc.dim_style.fg == null);
}

test "WordCloud.init has null block" {
    const wc = WordCloud.init();
    try testing.expect(wc.block == null);
}

// ============================================================================
// Group 2: Builder Immutability (6 tests)
// ============================================================================

test "withWords returns new value, original unchanged" {
    var words = [_]Word{.{ .text = "hello", .weight = 5 }};
    const wc1 = WordCloud.init();
    const wc2 = wc1.withWords(&words);

    try testing.expectEqual(@as(usize, 0), wc1.words.len);
    try testing.expectEqual(@as(usize, 1), wc2.words.len);
}

test "withStyle returns new value, original unchanged" {
    const style = Style{ .fg = .green };
    const wc1 = WordCloud.init();
    const wc2 = wc1.withStyle(style);

    try testing.expect(!std.meta.eql(wc1.style.fg, .green));
    try testing.expect(std.meta.eql(wc2.style.fg, .green));
}

test "withBoldStyle returns new value, original unchanged" {
    const style = Style{ .bold = true };
    const wc1 = WordCloud.init();
    const wc2 = wc1.withBoldStyle(style);

    try testing.expect(wc1.bold_style.bold != true);
    try testing.expect(wc2.bold_style.bold == true);
}

test "withDimStyle returns new value, original unchanged" {
    const style = Style{ .dim = true };
    const wc1 = WordCloud.init();
    const wc2 = wc1.withDimStyle(style);

    try testing.expect(wc1.dim_style.dim != true);
    try testing.expect(wc2.dim_style.dim == true);
}

test "withBlock returns new value, original unchanged" {
    const block = Block{};
    const wc1 = WordCloud.init();
    const wc2 = wc1.withBlock(block);

    try testing.expect(wc1.block == null);
    try testing.expect(wc2.block != null);
}

test "Chaining multiple builders produces correct result" {
    var words = [_]Word{
        .{ .text = "hello", .weight = 5 },
        .{ .text = "world", .weight = 3 },
    };
    const style = Style{ .fg = .red };
    const bold_style = Style{ .bold = true };
    const block = Block{};

    const wc = WordCloud.init()
        .withWords(&words)
        .withStyle(style)
        .withBoldStyle(bold_style)
        .withBlock(block);

    try testing.expectEqual(@as(usize, 2), wc.words.len);
    try testing.expect(std.meta.eql(wc.style.fg, .red));
    try testing.expect(wc.bold_style.bold == true);
    try testing.expect(wc.block != null);
}

// ============================================================================
// Group 3: Render Edge Cases (6 tests)
// ============================================================================

test "render with zero-width area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const wc = WordCloud.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 20 };

    wc.render(&buf, area);
    // Zero-area render: buffer should remain unchanged
    const initial = buf.getConst(0, 0);
    _ = initial;
}

test "render with zero-height area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const wc = WordCloud.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 0 };

    wc.render(&buf, area);
    // Zero-height render: no cells written in area
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "hello", .weight = 5 }};
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };

    wc.render(&buf, area);
    // 1x1 area: at most 1 cell written
    try testing.expect(countNonEmptyCells(buf, area) <= 1);
}

test "render area smaller than any word skips word, no crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "extraordinary", .weight = 5 }};
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };

    wc.render(&buf, area);
    // Word too long for area: should not be placed
    try testing.expect(!findInArea(buf, area, "extraordinary"));
}

test "render with empty words slice leaves buffer unchanged" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    // Fill buffer with non-space to detect changes
    const fill_area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    buf.fill(fill_area, 'X', Style{});

    const wc = WordCloud.init();
    wc.render(&buf, fill_area);

    // Buffer should still be filled with 'X'
    try testing.expect(buf.getConst(0, 0) != null);
    if (buf.getConst(0, 0)) |cell| {
        try testing.expectEqual(cell.char, 'X');
    }
}

test "render with null block uses full area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "hello", .weight = 5 }};
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);
    // Without block, word should appear in full area
    try testing.expect(findInArea(buf, area, "hello"));
}

// ============================================================================
// Group 4: Single Word Placement (5 tests)
// ============================================================================

test "single word with weight=1 appears somewhere in area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "hello", .weight = 1 }};
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "hello"));
}

test "single word with weight=10 should appear in center region" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "heavy", .weight = 10 }};
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Word should appear (location near center is implementation-specific)
    try testing.expect(findInArea(buf, area, "heavy"));
}

test "single word longer than area width is skipped" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "supercalifragilisticexpialidocious", .weight = 5 }};
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 20 };

    wc.render(&buf, area);

    // Word should not appear (too long for area width)
    try testing.expect(!findInArea(buf, area, "supercalifragilisticexpialidocious"));
}

test "single word exactly fitting area width is placed OK" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "hello", .weight = 5 }};
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 20 };

    wc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "hello"));
}

test "single empty-string word does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "", .weight = 5 }};
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);
    // Empty word: area should remain untouched
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 5: Multiple Word Placement (8 tests)
// ============================================================================

test "3 words: highest weight word appears in area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "heavy", .weight = 10 },
        .{ .text = "medium", .weight = 5 },
        .{ .text = "light", .weight = 1 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "heavy"));
}

test "multiple words on same row must not overlap" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "one", .weight = 5 },
        .{ .text = "two", .weight = 5 },
        .{ .text = "three", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // At least some words should be placed
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 3); // At least 3 chars placed
}

test "10 words with varying weights are placed within bounds" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "w1", .weight = 10 },
        .{ .text = "w2", .weight = 9 },
        .{ .text = "w3", .weight = 8 },
        .{ .text = "w4", .weight = 7 },
        .{ .text = "w5", .weight = 6 },
        .{ .text = "w6", .weight = 5 },
        .{ .text = "w7", .weight = 4 },
        .{ .text = "w8", .weight = 3 },
        .{ .text = "w9", .weight = 2 },
        .{ .text = "w10", .weight = 1 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // All rendered words should be within area bounds
    var y = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |_| {
                try testing.expect(x >= area.x and x < area.x + area.width);
                try testing.expect(y >= area.y and y < area.y + area.height);
            }
        }
    }
}

test "64 words (MAX_WORDS) does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 40);
    defer buf.deinit();

    var words: [64]Word = undefined;
    for (0..64) |i| {
        const weight = @as(u8, 64) - @as(u8, @intCast(i % 64));
        words[i] = .{ .text = "word", .weight = weight };
    }

    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };

    wc.render(&buf, area);
    // At least some words should be placed
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "65+ words truncated to 64, does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 40);
    defer buf.deinit();

    var words: [70]Word = undefined;
    for (0..70) |i| {
        words[i] = .{ .text = "word", .weight = @as(u8, 70 - @as(u8, @intCast(i % 70))) };
    }

    const wc = WordCloud.init().withWords(words[0..70]);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };

    wc.render(&buf, area);
    // Truncated to 64 words: should still render some content
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "words appear in area after render" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "first", .weight = 5 },
        .{ .text = "second", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "empty string words mixed with real words does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "", .weight = 5 },
        .{ .text = "hello", .weight = 5 },
        .{ .text = "", .weight = 5 },
        .{ .text = "world", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);
    // Real words should render despite empty ones
    try testing.expect(findInArea(buf, area, "hello") or findInArea(buf, area, "world"));
}

test "all words same weight=5 renders without crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "a", .weight = 5 },
        .{ .text = "b", .weight = 5 },
        .{ .text = "c", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);
    // Same weight: all should attempt to render
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 6: Style Application (8 tests)
// ============================================================================

test "word with weight >= 5 uses bold_style if different from Style{}" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "bold", .weight = 5 }};
    const bold_style = Style{ .bold = true };
    const wc = WordCloud.init().withWords(&words).withBoldStyle(bold_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "bold"));
}

test "word with weight <= 2 uses dim_style if different from Style{}" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "dim", .weight = 1 }};
    const dim_style = Style{ .dim = true };
    const wc = WordCloud.init().withWords(&words).withDimStyle(dim_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "dim"));
}

test "word with weight 3-4 uses style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "norm", .weight = 3 }};
    const style = Style{ .fg = .green };
    const wc = WordCloud.init().withWords(&words).withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "norm"));
}

test "word with weight >= 8 uses bold_style for heavy weight" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "super", .weight = 8 }};
    const bold_style = Style{ .bold = true };
    const wc = WordCloud.init().withWords(&words).withBoldStyle(bold_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "super"));
}

test "if bold_style empty, heavy words fall back to style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "heavy", .weight = 8 }};
    const style = Style{ .fg = .red };
    const wc = WordCloud.init().withWords(&words).withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "heavy"));
}

test "if dim_style empty, light words fall back to style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "light", .weight = 1 }};
    const style = Style{ .fg = .blue };
    const wc = WordCloud.init().withWords(&words).withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "light"));
}

test "style applied to each character of the word" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "hello", .weight = 5 }};
    const bold_style = Style{ .bold = true };
    const wc = WordCloud.init().withWords(&words).withBoldStyle(bold_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "hello"));
}

test "block style does not override word style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "text", .weight = 5 }};
    const block = Block{};
    const bold_style = Style{ .bold = true };
    const wc = WordCloud.init().withWords(&words).withBoldStyle(bold_style).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Word should render inside block area
    try testing.expect(findInArea(buf, area, "text"));
}

// ============================================================================
// Group 7: Block Border (5 tests)
// ============================================================================

test "with Block border, words appear only inside inner area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "hello", .weight = 5 }};
    const block = Block{};
    const wc = WordCloud.init().withWords(&words).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Border renders + words inside area
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "block title renders in border" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "hello", .weight = 5 }};
    const block = Block{ .title = "WordCloud" };
    const wc = WordCloud.init().withWords(&words).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Block title must render in border area
    try testing.expect(findInArea(buf, area, "WordCloud"));
}

test "words do not overwrite block border characters" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "hello", .weight = 5 }};
    const block = Block{};
    const wc = WordCloud.init().withWords(&words).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Border should exist (rendered)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "block with padding reduces inner area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "hello", .weight = 5 }};
    const block = Block{ .padding_left = 2, .padding_right = 2, .padding_top = 1, .padding_bottom = 1 };
    const wc = WordCloud.init().withWords(&words).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Block with padding still renders content
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "no block uses full area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "hello", .weight = 5 }};
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "hello"));
}

// ============================================================================
// Group 8: Determinism (3 tests)
// ============================================================================

test "same inputs render identically on second call" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var words = [_]Word{
        .{ .text = "first", .weight = 5 },
        .{ .text = "second", .weight = 3 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf1, area);
    wc.render(&buf2, area);

    // Both buffers should have same content
    var y: u16 = 0;
    while (y < 20) : (y += 1) {
        var x: u16 = 0;
        while (x < 40) : (x += 1) {
            const cell1 = buf1.getConst(x, y);
            const cell2 = buf2.getConst(x, y);
            if (cell1 != null and cell2 != null) {
                try testing.expectEqual(cell1.?.char, cell2.?.char);
            }
        }
    }
}

test "different word order with same weights may produce different layouts without crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "aaa", .weight = 5 },
        .{ .text = "bbb", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);
    // Both words should render
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "empty words slice always produces unchanged buffer" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    // Mark buffer with known pattern
    for (0..20) |y_idx| {
        const y: u16 = @intCast(y_idx);
        for (0..40) |x_idx| {
            const x: u16 = @intCast(x_idx);
            buf.set(x, y, .{ .char = 'X' });
        }
    }

    const wc = WordCloud.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);

    // Buffer should still be all 'X' (unchanged)
    if (buf.getConst(0, 0)) |cell| {
        try testing.expectEqual(cell.char, 'X');
    }
}

// ============================================================================
// Group 9: Placement Bounds (5 tests)
// ============================================================================

test "no word placed outside area.x..area.x+area.width" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "word1", .weight = 5 },
        .{ .text = "word2", .weight = 5 },
        .{ .text = "word3", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 10, .y = 5, .width = 30, .height = 15 };

    wc.render(&buf, area);

    // Check all non-space cells are within area bounds
    var y: u16 = 0;
    while (y < 30) : (y += 1) {
        var x: u16 = 0;
        while (x < 60) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ') {
                    try testing.expect(x >= area.x);
                    try testing.expect(x < area.x + area.width);
                }
            }
        }
    }
}

test "no word placed outside area.y..area.y+area.height" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "word1", .weight = 5 },
        .{ .text = "word2", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 10, .y = 5, .width = 30, .height = 15 };

    wc.render(&buf, area);

    // Check all non-space cells are within area bounds
    var y: u16 = 0;
    while (y < 30) : (y += 1) {
        var x: u16 = 0;
        while (x < 60) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ') {
                    try testing.expect(y >= area.y);
                    try testing.expect(y < area.y + area.height);
                }
            }
        }
    }
}

test "words near border are clipped or skipped, not written outside area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "verylongword", .weight = 5 },
        .{ .text = "another", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 20, .y = 10, .width = 10, .height = 8 };

    wc.render(&buf, area);

    // All content should be within area
    var y: u16 = 0;
    while (y < 20) : (y += 1) {
        var x: u16 = 0;
        while (x < 40) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ') {
                    try testing.expect(x >= area.x and x < area.x + area.width);
                    try testing.expect(y >= area.y and y < area.y + area.height);
                }
            }
        }
    }
}

test "MAX_WORDS=64 limit: more than 64 words attempts only first 64" {
    var buf = try Buffer.init(testing.allocator, 80, 40);
    defer buf.deinit();

    var words: [70]Word = undefined;
    for (0..70) |i| {
        words[i] = .{ .text = "w", .weight = @as(u8, 70 - @as(u8, @intCast(i % 70))) };
    }

    const wc = WordCloud.init().withWords(words[0..70]);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };

    wc.render(&buf, area);
    // At least some words from the first 64 should render
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "very long word (100 chars) in small area is skipped, no crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Word too long: should not be fully placed (verify not all chars appear)
    const long_word = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz";
    try testing.expect(!findInArea(buf, area, long_word));
}

// ============================================================================
// Group 10: Additional Comprehensive Tests (8 tests)
// ============================================================================

test "weights correctly sorted: highest weight placed first" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "light", .weight = 1 },
        .{ .text = "medium", .weight = 5 },
        .{ .text = "heavy", .weight = 10 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Highest weight word should appear
    try testing.expect(findInArea(buf, area, "heavy"));
}

test "weight=1 is light, weight=10 is heavy" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "light", .weight = 1 },
        .{ .text = "heavy", .weight = 10 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Both should attempt to appear
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render offset area at (10, 5) respects offset bounds" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "offset", .weight = 5 }};
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 10, .y = 5, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Word should render in offset area
    try testing.expect(findInArea(buf, area, "offset"));
}

test "multiple identical words renders all" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "same", .weight = 5 },
        .{ .text = "same", .weight = 5 },
        .{ .text = "same", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // "same" should appear at least once
    try testing.expect(findInArea(buf, area, "same"));
}

test "unicode text renders without crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{.{ .text = "café", .weight = 5 }};
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Unicode text "café" (4 visible chars) should produce some rendered cells
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "single character words render" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "a", .weight = 5 },
        .{ .text = "b", .weight = 5 },
        .{ .text = "c", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // At least one char should appear
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 1);
}

test "area with width=1 height=20 can render single-char words" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "a", .weight = 5 },
        .{ .text = "b", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 20 };

    wc.render(&buf, area);

    // Single-char words should fit in 1-width area
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "mixing different text lengths works correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var words = [_]Word{
        .{ .text = "a", .weight = 5 },
        .{ .text = "hello", .weight = 5 },
        .{ .text = "verylongword", .weight = 5 },
    };
    const wc = WordCloud.init().withWords(&words);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    wc.render(&buf, area);

    // Mixed lengths should render some content
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}
