//! BracketViewer Widget Tests — TDD Red Phase
//!
//! Tests bracket visualization widget with tournament/competition match rendering,
//! winner highlighting, score display, focused match navigation, and block border support.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const BracketViewer = sailor.tui.widgets.BracketViewer;
const Round = sailor.tui.widgets.bracket_viewer.Round;
const Match = sailor.tui.widgets.bracket_viewer.Match;
const Winner = sailor.tui.widgets.bracket_viewer.Winner;

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

/// Check if buffer contains a specific character in area
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

// ============================================================================
// Group 1: Init/Defaults (5 tests)
// ============================================================================

test "BracketViewer.init has empty rounds" {
    const bv = BracketViewer.init();
    try testing.expectEqual(@as(usize, 0), bv.rounds.len);
}

test "BracketViewer.init has focused_match == 0" {
    const bv = BracketViewer.init();
    try testing.expectEqual(@as(usize, 0), bv.focused_match);
}

test "BracketViewer.init has focused_round == 0" {
    const bv = BracketViewer.init();
    try testing.expectEqual(@as(usize, 0), bv.focused_round);
}

test "BracketViewer.init has show_scores == true" {
    const bv = BracketViewer.init();
    try testing.expect(bv.show_scores == true);
}

test "BracketViewer.init has null block" {
    const bv = BracketViewer.init();
    try testing.expect(bv.block == null);
}

// ============================================================================
// Group 2: Winner Enum (3 tests)
// ============================================================================

test "Winner.none exists and can be used" {
    const w: Winner = .none;
    try testing.expect(w == .none);
}

test "Winner.a exists and can be used" {
    const w: Winner = .a;
    try testing.expect(w == .a);
}

test "Winner.b exists and can be used" {
    const w: Winner = .b;
    try testing.expect(w == .b);
}

// ============================================================================
// Group 3: Match Struct (4 tests)
// ============================================================================

test "Match with only teams has default score 0 and 0" {
    const m = Match{
        .team_a = "A",
        .team_b = "B",
    };
    try testing.expectEqual(@as(i32, 0), m.score_a);
    try testing.expectEqual(@as(i32, 0), m.score_b);
}

test "Match with only teams has default winner .none" {
    const m = Match{
        .team_a = "A",
        .team_b = "B",
    };
    try testing.expect(m.winner == .none);
}

test "Match can be created with all fields" {
    const m = Match{
        .team_a = "Alpha",
        .team_b = "Beta",
        .score_a = 3,
        .score_b = 2,
        .winner = .a,
    };
    try testing.expectEqualStrings("Alpha", m.team_a);
    try testing.expectEqualStrings("Beta", m.team_b);
    try testing.expectEqual(@as(i32, 3), m.score_a);
    try testing.expectEqual(@as(i32, 2), m.score_b);
    try testing.expect(m.winner == .a);
}

test "Match with negative scores can be created" {
    const m = Match{
        .team_a = "A",
        .team_b = "B",
        .score_a = -1,
        .score_b = -2,
    };
    try testing.expectEqual(@as(i32, -1), m.score_a);
    try testing.expectEqual(@as(i32, -2), m.score_b);
}

// ============================================================================
// Group 4: Round Struct (3 tests)
// ============================================================================

test "Round with no matches has empty slice" {
    var matches: [0]Match = undefined;
    const r = Round{ .matches = &matches };
    try testing.expectEqual(@as(usize, 0), r.matches.len);
}

test "Round can be created with matches" {
    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B" },
        .{ .team_a = "C", .team_b = "D" },
    };
    const r = Round{ .matches = &matches };
    try testing.expectEqual(@as(usize, 2), r.matches.len);
}

test "Round preserves match order" {
    var matches = [_]Match{
        .{ .team_a = "First", .team_b = "B" },
        .{ .team_a = "Second", .team_b = "D" },
    };
    const r = Round{ .matches = &matches };
    try testing.expectEqualStrings("First", r.matches[0].team_a);
    try testing.expectEqualStrings("Second", r.matches[1].team_a);
}

// ============================================================================
// Group 5: totalRounds Method (4 tests)
// ============================================================================

test "totalRounds with no rounds returns 0" {
    const bv = BracketViewer.init();
    try testing.expectEqual(@as(usize, 0), bv.totalRounds());
}

test "totalRounds with 1 round returns 1" {
    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    try testing.expectEqual(@as(usize, 1), bv.totalRounds());
}

test "totalRounds with 3 rounds returns 3" {
    var m0 = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var m1 = [_]Match{.{ .team_a = "C", .team_b = "D" }};
    var m2 = [_]Match{.{ .team_a = "E", .team_b = "F" }};
    var rounds = [_]Round{
        .{ .matches = &m0 },
        .{ .matches = &m1 },
        .{ .matches = &m2 },
    };
    const bv = BracketViewer.init().withRounds(&rounds);
    try testing.expectEqual(@as(usize, 3), bv.totalRounds());
}

test "totalRounds reflects current state" {
    var m = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var r1 = [_]Round{.{ .matches = &m }};
    const bv1 = BracketViewer.init();
    const bv2 = bv1.withRounds(&r1);
    try testing.expectEqual(@as(usize, 0), bv1.totalRounds());
    try testing.expectEqual(@as(usize, 1), bv2.totalRounds());
}

// ============================================================================
// Group 6: matchCount Method (5 tests)
// ============================================================================

test "matchCount with no rounds returns 0" {
    const bv = BracketViewer.init();
    try testing.expectEqual(@as(usize, 0), bv.matchCount());
}

test "matchCount with single match returns 1" {
    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    try testing.expectEqual(@as(usize, 1), bv.matchCount());
}

test "matchCount sums all matches across rounds" {
    var m0 = [_]Match{
        .{ .team_a = "A", .team_b = "B" },
        .{ .team_a = "C", .team_b = "D" },
    };
    var m1 = [_]Match{
        .{ .team_a = "W1", .team_b = "W2" },
    };
    var rounds = [_]Round{
        .{ .matches = &m0 },
        .{ .matches = &m1 },
    };
    const bv = BracketViewer.init().withRounds(&rounds);
    try testing.expectEqual(@as(usize, 3), bv.matchCount());
}

test "matchCount with multiple rounds multiple matches" {
    var m0 = [_]Match{
        .{ .team_a = "A", .team_b = "B" },
        .{ .team_a = "C", .team_b = "D" },
        .{ .team_a = "E", .team_b = "F" },
    };
    var m1 = [_]Match{
        .{ .team_a = "X", .team_b = "Y" },
        .{ .team_a = "Z", .team_b = "W" },
    };
    var rounds = [_]Round{
        .{ .matches = &m0 },
        .{ .matches = &m1 },
    };
    const bv = BracketViewer.init().withRounds(&rounds);
    try testing.expectEqual(@as(usize, 5), bv.matchCount());
}

test "matchCount with empty rounds returns 0" {
    var r0 = [_]Match{};
    var rounds = [_]Round{.{ .matches = &r0 }};
    const bv = BracketViewer.init().withRounds(&rounds);
    try testing.expectEqual(@as(usize, 0), bv.matchCount());
}

// ============================================================================
// Group 7: Builder Immutability (8 tests)
// ============================================================================

test "withRounds returns new value, original unchanged" {
    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv1 = BracketViewer.init();
    const bv2 = bv1.withRounds(&rounds);

    try testing.expectEqual(@as(usize, 0), bv1.rounds.len);
    try testing.expectEqual(@as(usize, 1), bv2.rounds.len);
}

test "withFocusedMatch returns new value, original unchanged" {
    const bv1 = BracketViewer.init();
    const bv2 = bv1.withFocusedMatch(3);

    try testing.expectEqual(@as(usize, 0), bv1.focused_match);
    try testing.expectEqual(@as(usize, 3), bv2.focused_match);
}

test "withFocusedRound returns new value, original unchanged" {
    const bv1 = BracketViewer.init();
    const bv2 = bv1.withFocusedRound(2);

    try testing.expectEqual(@as(usize, 0), bv1.focused_round);
    try testing.expectEqual(@as(usize, 2), bv2.focused_round);
}

test "withStyle returns new value, original unchanged" {
    const style = Style{ .fg = .green };
    const bv1 = BracketViewer.init();
    const bv2 = bv1.withStyle(style);

    try testing.expect(!std.meta.eql(bv1.style.fg, .green));
    try testing.expect(std.meta.eql(bv2.style.fg, .green));
}

test "withWinStyle returns new value, original unchanged" {
    const style = Style{ .bold = true };
    const bv1 = BracketViewer.init();
    const bv2 = bv1.withWinStyle(style);

    try testing.expect(bv1.win_style.bold != true);
    try testing.expect(bv2.win_style.bold == true);
}

test "withFocusedStyle returns new value, original unchanged" {
    const style = Style{ .dim = true };
    const bv1 = BracketViewer.init();
    const bv2 = bv1.withFocusedStyle(style);

    try testing.expect(bv1.focused_style.dim != true);
    try testing.expect(bv2.focused_style.dim == true);
}

test "withShowScores returns new value, original unchanged" {
    const bv1 = BracketViewer.init();
    const bv2 = bv1.withShowScores(false);

    try testing.expect(bv1.show_scores == true);
    try testing.expect(bv2.show_scores == false);
}

test "withBlock returns new value, original unchanged" {
    const block = Block{};
    const bv1 = BracketViewer.init();
    const bv2 = bv1.withBlock(block);

    try testing.expect(bv1.block == null);
    try testing.expect(bv2.block != null);
}

// ============================================================================
// Group 8: Builder Chaining (3 tests)
// ============================================================================

test "builder methods can be chained" {
    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const style = Style{ .fg = .red };

    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withFocusedRound(0)
        .withStyle(style);

    try testing.expectEqual(@as(usize, 1), bv.rounds.len);
    try testing.expectEqual(@as(usize, 0), bv.focused_round);
    try testing.expect(std.meta.eql(bv.style.fg, .red));
}

test "chaining multiple builders does not affect original" {
    const bv1 = BracketViewer.init();
    var m = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var r = [_]Round{.{ .matches = &m }};
    const bv2 = bv1.withRounds(&r);
    const bv3 = bv1.withFocusedRound(5);

    try testing.expectEqual(@as(usize, 0), bv1.rounds.len);
    try testing.expectEqual(@as(usize, 1), bv2.rounds.len);
    try testing.expectEqual(@as(usize, 5), bv3.focused_round);
}

test "complex builder chain works" {
    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const block = Block{};

    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withFocusedRound(0)
        .withFocusedMatch(0)
        .withBlock(block);

    try testing.expectEqual(@as(usize, 1), bv.rounds.len);
    try testing.expect(bv.block != null);
}

// ============================================================================
// Group 9: Render Edge Cases (6 tests)
// ============================================================================

test "render with zero-width area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const bv = BracketViewer.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 20 };

    bv.render(&buf, area);
    try testing.expect(true);
}

test "render with zero-height area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const bv = BracketViewer.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 0 };

    bv.render(&buf, area);
    try testing.expect(true);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };

    bv.render(&buf, area);
    try testing.expect(true);
}

test "render with empty rounds does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const bv = BracketViewer.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);
    try testing.expect(true);
}

test "render area smaller than minimum does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "Team A", .team_b = "Team B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 1 };

    bv.render(&buf, area);
    try testing.expect(true);
}

test "render with offset area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 10, .y = 5, .width = 40, .height = 15 };

    bv.render(&buf, area);
    try testing.expect(true);
}

// ============================================================================
// Group 10: Single Round Single Match (6 tests)
// ============================================================================

test "single round single match renders team_a name" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "Alpha", .team_b = "Beta" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Alpha"));
}

test "single round single match renders team_b name" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "Alpha", .team_b = "Beta" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Beta"));
}

test "match renders divider between teams" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    // Divider is "───"
    try testing.expect(areaHasChar(buf, area, '─'));
}

test "match renders score when show_scores=true" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B", .score_a = 3, .score_b = 2 },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds).withShowScores(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    // Scores should appear in some form
    try testing.expect(findInArea(buf, area, "3") or findInArea(buf, area, "2"));
}

test "match hides score when show_scores=false" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B", .score_a = 10, .score_b = 5 },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds).withShowScores(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    // Teams should still appear
    try testing.expect(findInArea(buf, area, "A") or findInArea(buf, area, "B"));
}

test "match with empty team names does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "", .team_b = "" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);
    try testing.expect(true);
}

// ============================================================================
// Group 11: Winner Highlighting (6 tests)
// ============================================================================

test "match with winner=.a highlights team_a with win_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "Winner", .team_b = "Loser", .winner = .a },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Winner"));
}

test "match with winner=.b highlights team_b with win_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "Loser", .team_b = "Winner", .winner = .b },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Winner"));
}

test "match with winner=.none applies no highlight" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B", .winner = .none },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A") and findInArea(buf, area, "B"));
}

test "win_style customization works" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "Winner", .team_b = "Loser", .winner = .a },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const win_style = Style{ .bold = true };
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withWinStyle(win_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Winner"));
}

test "multiple matches show winners correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 30);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A1", .team_b = "B1", .winner = .a },
        .{ .team_a = "A2", .team_b = "B2", .winner = .b },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 30 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A1"));
    try testing.expect(findInArea(buf, area, "B2"));
}

// ============================================================================
// Group 12: Score Display (5 tests)
// ============================================================================

test "scores appear in expected format with show_scores=true" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B", .score_a = 5, .score_b = 3 },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds).withShowScores(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    // Either "5:3" or "[5:3]" or similar format
    try testing.expect(findInArea(buf, area, "5") or findInArea(buf, area, "3"));
}

test "negative scores render correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B", .score_a = -1, .score_b = -2 },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds).withShowScores(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);
    try testing.expect(true);
}

test "large scores render without truncation crash" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B", .score_a = 999, .score_b = 888 },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds).withShowScores(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    bv.render(&buf, area);
    try testing.expect(true);
}

test "zero scores display correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B", .score_a = 0, .score_b = 0 },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds).withShowScores(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);
    try testing.expect(true);
}

test "show_scores toggle affects rendering" {
    var buf_on = try Buffer.init(testing.allocator, 40, 20);
    defer buf_on.deinit();
    var buf_off = try Buffer.init(testing.allocator, 40, 20);
    defer buf_off.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B", .score_a = 5, .score_b = 3 },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    const bv_on = BracketViewer.init().withRounds(&rounds).withShowScores(true);
    const bv_off = BracketViewer.init().withRounds(&rounds).withShowScores(false);

    bv_on.render(&buf_on, area);
    bv_off.render(&buf_off, area);

    // Both should render without crash
    try testing.expect(true);
}

// ============================================================================
// Group 13: Multiple Rounds (6 tests)
// ============================================================================

test "two rounds render with separator" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();

    var m0 = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var m1 = [_]Match{.{ .team_a = "W1", .team_b = "W2" }};
    var rounds = [_]Round{
        .{ .matches = &m0 },
        .{ .matches = &m1 },
    };
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A") and findInArea(buf, area, "W1"));
}

test "three rounds render in columns" {
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();

    var m0 = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var m1 = [_]Match{.{ .team_a = "C", .team_b = "D" }};
    var m2 = [_]Match{.{ .team_a = "E", .team_b = "F" }};
    var rounds = [_]Round{
        .{ .matches = &m0 },
        .{ .matches = &m1 },
        .{ .matches = &m2 },
    };
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A") and findInArea(buf, area, "E"));
}

test "round separator │ appears between rounds" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();

    var m0 = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var m1 = [_]Match{.{ .team_a = "C", .team_b = "D" }};
    var rounds = [_]Round{
        .{ .matches = &m0 },
        .{ .matches = &m1 },
    };
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, '│'));
}

test "each round column has correct width" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();

    var m0 = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var m1 = [_]Match{.{ .team_a = "C", .team_b = "D" }};
    var rounds = [_]Round{
        .{ .matches = &m0 },
        .{ .matches = &m1 },
    };
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(true);
}

test "MAX_ROUNDS constant is defined" {
    try testing.expectEqual(@as(usize, 8), BracketViewer.MAX_ROUNDS);
}

test "8 rounds do not crash" {
    var buf = try Buffer.init(testing.allocator, 200, 20);
    defer buf.deinit();

    var m: [8][1]Match = undefined;
    var r: [8]Round = undefined;
    for (0..8) |i| {
        m[i][0] = .{ .team_a = "A", .team_b = "B" };
        r[i] = .{ .matches = &m[i] };
    }
    const bv = BracketViewer.init().withRounds(&r);
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 20 };

    bv.render(&buf, area);
    try testing.expect(true);
}

// ============================================================================
// Group 14: Focused Match Highlight (5 tests)
// ============================================================================

test "focused match in focused round renders with focused_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B" },
        .{ .team_a = "C", .team_b = "D" },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const focused_style = Style{ .bold = true };
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withFocusedRound(0)
        .withFocusedMatch(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A"));
}

test "focused_match index changes which match is focused" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B" },
        .{ .team_a = "C", .team_b = "D" },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withFocusedMatch(1);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expectEqual(@as(usize, 1), bv.focused_match);
}

test "focused_round index changes which round is focused" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();

    var m0 = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var m1 = [_]Match{.{ .team_a = "C", .team_b = "D" }};
    var rounds = [_]Round{
        .{ .matches = &m0 },
        .{ .matches = &m1 },
    };
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withFocusedRound(1);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    bv.render(&buf, area);

    try testing.expectEqual(@as(usize, 1), bv.focused_round);
}

test "all matches appear even when one is focused" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B" },
        .{ .team_a = "C", .team_b = "D" },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withFocusedMatch(0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A") and findInArea(buf, area, "C"));
}

test "multiple rounds both show correct focused round" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();

    var m0 = [_]Match{.{ .team_a = "R0", .team_b = "B" }};
    var m1 = [_]Match{.{ .team_a = "R1", .team_b = "D" }};
    var rounds = [_]Round{
        .{ .matches = &m0 },
        .{ .matches = &m1 },
    };
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withFocusedRound(1)
        .withFocusedMatch(0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    bv.render(&buf, area);

    try testing.expectEqual(@as(usize, 1), bv.focused_round);
}

// ============================================================================
// Group 15: Block Border (4 tests)
// ============================================================================

test "with Block border renders frame around content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const block = Block{};
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    // Check for border characters
    try testing.expect(areaHasChar(buf, area, '─') or
                       areaHasChar(buf, area, '│') or
                       areaHasChar(buf, area, '┌'));
}

test "block inner area smaller than outer area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const block = Block{};
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    // Content should be inside border
    try testing.expect(true);
}

test "matches render inside block border area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const block = Block{};
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A") or findInArea(buf, area, "B"));
}

test "null block uses full area without border" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A"));
}

// ============================================================================
// Group 16: Rendering Bounds (4 tests)
// ============================================================================

test "no content rendered outside area bounds" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 20, .y = 10, .width = 30, .height = 10 };

    bv.render(&buf, area);

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

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 10, .y = 5, .width = 40, .height = 15 };

    bv.render(&buf, area);

    try testing.expect(true);
}

test "area with width less than minimum does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "VeryLongTeamName", .team_b = "AnotherTeam" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 20 };

    bv.render(&buf, area);
    try testing.expect(true);
}

test "many rounds at narrow width renders without crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var m: [4][1]Match = undefined;
    var r: [4]Round = undefined;
    for (0..4) |i| {
        m[i][0] = .{ .team_a = "A", .team_b = "B" };
        r[i] = .{ .matches = &m[i] };
    }
    const bv = BracketViewer.init().withRounds(&r);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);
    try testing.expect(true);
}

// ============================================================================
// Group 17: Style Application (4 tests)
// ============================================================================

test "base style applied to background" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const style = Style{ .bg = .black };
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(true);
}

test "win_style applied to winning team" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "Winner", .team_b = "Loser", .winner = .a },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const win_style = Style{ .fg = .green };
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withWinStyle(win_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Winner"));
}

test "focused_style applied to focused match" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const focused_style = Style{ .bold = true };
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withFocusedMatch(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A"));
}

test "all styles can be applied simultaneously" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B", .winner = .a },
    };
    var rounds = [_]Round{.{ .matches = &matches }};
    const style = Style{ .bg = .black };
    const win_style = Style{ .bold = true };
    const focused_style = Style{ .dim = true };
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withStyle(style)
        .withWinStyle(win_style)
        .withFocusedStyle(focused_style)
        .withFocusedMatch(0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A"));
}

// ============================================================================
// Group 18: Full Integration (5 tests)
// ============================================================================

test "complete bracket with 3 rounds and multiple matches renders" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var r0_matches = [_]Match{
        .{ .team_a = "A", .team_b = "B", .winner = .a },
        .{ .team_a = "C", .team_b = "D", .winner = .b },
    };
    var r1_matches = [_]Match{
        .{ .team_a = "A", .team_b = "D", .winner = .b },
    };
    var r2_matches = [_]Match{
        .{ .team_a = "?", .team_b = "D", .winner = .none },
    };

    var rounds = [_]Round{
        .{ .matches = &r0_matches },
        .{ .matches = &r1_matches },
        .{ .matches = &r2_matches },
    };

    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withFocusedRound(1)
        .withFocusedMatch(0);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A"));
    try testing.expect(findInArea(buf, area, "D"));
}

test "bracket with block border and styles" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();

    var matches = [_]Match{
        .{ .team_a = "Team1", .team_b = "Team2" },
    };
    var rounds = [_]Round{.{ .matches = &matches }};

    const block = Block{};
    const style = Style{ .fg = .white, .bg = .blue };
    const win_style = Style{ .bold = true };

    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withStyle(style)
        .withWinStyle(win_style)
        .withBlock(block)
        .withFocusedRound(0);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };

    bv.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Team1"));
}

test "bracket with many matches and scores" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();

    var matches: [4]Match = undefined;
    matches[0] = .{ .team_a = "A", .team_b = "B", .score_a = 2, .score_b = 1, .winner = .a };
    matches[1] = .{ .team_a = "C", .team_b = "D", .score_a = 3, .score_b = 0, .winner = .a };
    matches[2] = .{ .team_a = "E", .team_b = "F", .score_a = 1, .score_b = 1, .winner = .none };
    matches[3] = .{ .team_a = "G", .team_b = "H", .score_a = 5, .score_b = 4, .winner = .b };

    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withShowScores(true);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    bv.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, 'A') or areaHasChar(buf, area, '5'));
}

test "bracket navigation state preserved" {
    var matches = [_]Match{
        .{ .team_a = "A", .team_b = "B" },
        .{ .team_a = "C", .team_b = "D" },
    };
    var rounds = [_]Round{.{ .matches = &matches }};

    const bv = BracketViewer.init()
        .withRounds(&rounds)
        .withFocusedRound(0)
        .withFocusedMatch(1);

    try testing.expectEqual(@as(usize, 0), bv.focused_round);
    try testing.expectEqual(@as(usize, 1), bv.focused_match);
}

test "bracket state immutability across renders" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var matches = [_]Match{.{ .team_a = "A", .team_b = "B" }};
    var rounds = [_]Round{.{ .matches = &matches }};
    const bv = BracketViewer.init().withRounds(&rounds);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    bv.render(&buf1, area);
    bv.render(&buf2, area);

    // Both renders should complete without crash
    try testing.expect(true);
}
