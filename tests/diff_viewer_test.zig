//! DiffViewer tests — v2.16.0
//!
//! Tests unified diff line classification, line/count queries, and rendering.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;

const DiffViewer = sailor.tui.widgets.DiffViewer;
const LineKind = sailor.tui.widgets.DiffViewerLineKind;
const classifyLine = sailor.tui.widgets.diffViewerClassifyLine;

// ============================================================================
// Line classification
// ============================================================================

test "classifyLine — diff_header variants" {
    try testing.expectEqual(LineKind.diff_header, classifyLine("diff --git a/foo.zig b/foo.zig"));
    try testing.expectEqual(LineKind.diff_header, classifyLine("index abc123..def456 100644"));
    try testing.expectEqual(LineKind.diff_header, classifyLine("new file mode 100644"));
    try testing.expectEqual(LineKind.diff_header, classifyLine("deleted file mode 100644"));
    try testing.expectEqual(LineKind.diff_header, classifyLine("old mode 100755"));
    try testing.expectEqual(LineKind.diff_header, classifyLine("new mode 100644"));
    try testing.expectEqual(LineKind.diff_header, classifyLine("rename from old/path.zig"));
    try testing.expectEqual(LineKind.diff_header, classifyLine("rename to new/path.zig"));
    try testing.expectEqual(LineKind.diff_header, classifyLine("similarity index 95%"));
    try testing.expectEqual(LineKind.diff_header, classifyLine("Binary files a/img.png and b/img.png differ"));
}

test "classifyLine — file_header" {
    try testing.expectEqual(LineKind.file_header, classifyLine("--- a/foo.zig"));
    try testing.expectEqual(LineKind.file_header, classifyLine("+++ b/foo.zig"));
    try testing.expectEqual(LineKind.file_header, classifyLine("--- /dev/null"));
    try testing.expectEqual(LineKind.file_header, classifyLine("+++ /dev/null"));
}

test "classifyLine — hunk_header" {
    try testing.expectEqual(LineKind.hunk_header, classifyLine("@@ -1,4 +1,6 @@"));
    try testing.expectEqual(LineKind.hunk_header, classifyLine("@@ -0,0 +1 @@"));
    try testing.expectEqual(LineKind.hunk_header, classifyLine("@@ -100,10 +100,12 @@ fn foo() void {"));
}

test "classifyLine — removed" {
    try testing.expectEqual(LineKind.removed, classifyLine("-old line"));
    try testing.expectEqual(LineKind.removed, classifyLine("-"));
    try testing.expectEqual(LineKind.removed, classifyLine("-   trailing spaces   "));
}

test "classifyLine — added" {
    try testing.expectEqual(LineKind.added, classifyLine("+new line"));
    try testing.expectEqual(LineKind.added, classifyLine("+"));
    try testing.expectEqual(LineKind.added, classifyLine("+// comment"));
}

test "classifyLine — context" {
    try testing.expectEqual(LineKind.context, classifyLine(" unchanged line"));
    try testing.expectEqual(LineKind.context, classifyLine(""));
    try testing.expectEqual(LineKind.context, classifyLine("no prefix line"));
}

test "classifyLine — no_newline" {
    try testing.expectEqual(LineKind.no_newline, classifyLine("\\ No newline at end of file"));
}

test "classifyLine — file_header takes priority over removed/added" {
    // "--- " is file_header, not removed
    try testing.expectEqual(LineKind.file_header, classifyLine("--- a/file"));
    // "+++ " is file_header, not added
    try testing.expectEqual(LineKind.file_header, classifyLine("+++ b/file"));
    // bare "---" without space is removed
    try testing.expectEqual(LineKind.removed, classifyLine("---separator"));
}

// ============================================================================
// lineCount
// ============================================================================

test "lineCount — empty" {
    const v = DiffViewer{};
    try testing.expectEqual(@as(usize, 0), v.lineCount());
}

test "lineCount — single line" {
    const v = DiffViewer{ .content = "+hello" };
    try testing.expectEqual(@as(usize, 1), v.lineCount());
}

test "lineCount — multi-line diff" {
    const diff =
        \\diff --git a/foo.zig b/foo.zig
        \\@@ -1,2 +1,3 @@
        \\ context
        \\-removed
        \\+added
    ;
    const v = DiffViewer{ .content = diff };
    try testing.expectEqual(@as(usize, 5), v.lineCount());
}

// ============================================================================
// counts()
// ============================================================================

test "counts — empty" {
    const v = DiffViewer{};
    const c = v.counts();
    try testing.expectEqual(@as(usize, 0), c.added);
    try testing.expectEqual(@as(usize, 0), c.removed);
    try testing.expectEqual(@as(usize, 0), c.hunks);
}

test "counts — typical diff" {
    const diff =
        \\@@ -1,3 +1,4 @@
        \\ context
        \\-line1
        \\-line2
        \\+new1
        \\+new2
        \\+new3
    ;
    const v = DiffViewer{ .content = diff };
    const c = v.counts();
    try testing.expectEqual(@as(usize, 1), c.hunks);
    try testing.expectEqual(@as(usize, 2), c.removed);
    try testing.expectEqual(@as(usize, 3), c.added);
}

test "counts — multiple hunks" {
    const diff =
        \\@@ -1,2 +1,2 @@
        \\-a
        \\+b
        \\@@ -10,2 +10,2 @@
        \\-c
        \\+d
    ;
    const v = DiffViewer{ .content = diff };
    const c = v.counts();
    try testing.expectEqual(@as(usize, 2), c.hunks);
    try testing.expectEqual(@as(usize, 2), c.removed);
    try testing.expectEqual(@as(usize, 2), c.added);
}

// ============================================================================
// Builder methods
// ============================================================================

test "withContent preserves other fields" {
    const v = DiffViewer{ .scroll = 5, .h_scroll = 3 };
    const v2 = v.withContent("+line");
    try testing.expectEqualStrings("+line", v2.content);
    try testing.expectEqual(@as(usize, 5), v2.scroll);
    try testing.expectEqual(@as(usize, 3), v2.h_scroll);
}

test "withScroll does not mutate original" {
    const v = DiffViewer{};
    const v2 = v.withScroll(7);
    try testing.expectEqual(@as(usize, 7), v2.scroll);
    try testing.expectEqual(@as(usize, 0), v.scroll);
}

test "withHScroll builder" {
    const v = DiffViewer{};
    const v2 = v.withHScroll(4);
    try testing.expectEqual(@as(usize, 4), v2.h_scroll);
    try testing.expectEqual(@as(usize, 0), v.h_scroll);
}

// ============================================================================
// Render — basic correctness
// ============================================================================

fn makeBuffer(allocator: std.mem.Allocator, w: u16, h: u16) !Buffer {
    return Buffer.init(allocator, w, h);
}

test "render — removed line is red" {
    var buf = try makeBuffer(testing.allocator, 40, 5);
    defer buf.deinit();

    const v = DiffViewer{ .content = "-deleted line" };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 5 });

    const cell = buf.get(0, 0);
    try testing.expectEqual(@as(u21, '-'), cell.?.char);
    try testing.expectEqual(Color.red, cell.?.style.fg.?);
}

test "render — added line is green" {
    var buf = try makeBuffer(testing.allocator, 40, 5);
    defer buf.deinit();

    const v = DiffViewer{ .content = "+new line" };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 5 });

    const cell = buf.get(0, 0);
    try testing.expectEqual(@as(u21, '+'), cell.?.char);
    try testing.expectEqual(Color.green, cell.?.style.fg.?);
}

test "render — hunk header is cyan bold" {
    var buf = try makeBuffer(testing.allocator, 40, 5);
    defer buf.deinit();

    const v = DiffViewer{ .content = "@@ -1,2 +1,3 @@" };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 5 });

    const cell = buf.get(0, 0);
    try testing.expectEqual(@as(u21, '@'), cell.?.char);
    try testing.expectEqual(Color.cyan, cell.?.style.fg.?);
    try testing.expect(cell.?.style.bold);
}

test "render — file header is bold" {
    var buf = try makeBuffer(testing.allocator, 40, 5);
    defer buf.deinit();

    const v = DiffViewer{ .content = "--- a/foo.zig" };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 5 });

    const cell = buf.get(0, 0);
    try testing.expectEqual(@as(u21, '-'), cell.?.char);
    try testing.expect(cell.?.style.bold);
}

test "render — context line uses default style" {
    var buf = try makeBuffer(testing.allocator, 40, 5);
    defer buf.deinit();

    const v = DiffViewer{ .content = " unchanged" };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 5 });

    const cell = buf.get(0, 0);
    try testing.expectEqual(@as(u21, ' '), cell.?.char);
    try testing.expect(cell.?.style.fg == null);
}

test "render — vertical scroll skips lines" {
    var buf = try makeBuffer(testing.allocator, 40, 5);
    defer buf.deinit();

    const diff =
        \\--- a/f
        \\+++ b/f
        \\@@ -1 +1 @@
        \\-old
        \\+new
    ;
    const v = DiffViewer{ .content = diff, .scroll = 2 };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 5 });

    // Row 0 after scroll=2 is the hunk header
    const cell = buf.get(0, 0);
    try testing.expectEqual(@as(u21, '@'), cell.?.char);
}

test "render — h_scroll trims prefix columns" {
    var buf = try makeBuffer(testing.allocator, 10, 3);
    defer buf.deinit();

    const v = DiffViewer{ .content = "+hello world", .h_scroll = 1 };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 3 });

    // After skipping '+', first char should be 'h'
    try testing.expectEqual(@as(u21, 'h'), buf.get(0, 0).?.char);
}

test "render — h_scroll beyond line length renders blank" {
    var buf = try makeBuffer(testing.allocator, 10, 3);
    defer buf.deinit();

    const v = DiffViewer{ .content = "+hi", .h_scroll = 100 };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 3 });

    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "render — zero width area is safe (no panic)" {
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit();

    const v = DiffViewer{ .content = "+line" };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 5 });
}

test "render — zero height area is safe (no panic)" {
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit();

    const v = DiffViewer{ .content = "+line" };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 0 });
}

test "render — content clipped to area width" {
    var buf = try makeBuffer(testing.allocator, 5, 3);
    defer buf.deinit();

    // 20-char line rendered into 5-col area
    const v = DiffViewer{ .content = "+abcdefghijklmnopqrst" };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 5, .height = 3 });

    try testing.expectEqual(@as(u21, '+'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'a'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'd'), buf.get(4, 0).?.char);
    // Col 5 is beyond area width — not rendered
}

test "render — empty content renders nothing" {
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit();

    const v = DiffViewer{};
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });

    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "render — multi-line diff renders all kinds" {
    var buf = try makeBuffer(testing.allocator, 40, 10);
    defer buf.deinit();

    const diff =
        \\--- a/foo.zig
        \\+++ b/foo.zig
        \\@@ -1,2 +1,3 @@
        \\ context
        \\-removed line
        \\+added line
    ;
    const v = DiffViewer{ .content = diff };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 10 });

    // Row 0: "--- a/foo.zig" — file_header (bold)
    try testing.expect(buf.get(0, 0).?.style.bold);
    // Row 2: "@@ ..." — hunk_header (cyan)
    try testing.expectEqual(Color.cyan, buf.get(0, 2).?.style.fg.?);
    // Row 4: "-removed..." — removed (red)
    try testing.expectEqual(Color.red, buf.get(0, 4).?.style.fg.?);
    // Row 5: "+added..." — added (green)
    try testing.expectEqual(Color.green, buf.get(0, 5).?.style.fg.?);
}

test "render — diff_header line uses header_style" {
    var buf = try makeBuffer(testing.allocator, 50, 3);
    defer buf.deinit();

    const v = DiffViewer{ .content = "diff --git a/foo b/foo" };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 50, .height = 3 });

    const cell = buf.get(0, 0);
    try testing.expectEqual(@as(u21, 'd'), cell.?.char);
    try testing.expectEqual(Color.bright_black, cell.?.style.fg.?);
    try testing.expect(cell.?.style.bold);
}

test "render — no_newline line" {
    var buf = try makeBuffer(testing.allocator, 40, 3);
    defer buf.deinit();

    const v = DiffViewer{ .content = "\\ No newline at end of file" };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 3 });

    const cell = buf.get(0, 0);
    try testing.expectEqual(@as(u21, '\\'), cell.?.char);
    try testing.expectEqual(Color.yellow, cell.?.style.fg.?);
}

test "render — custom removed_style is applied" {
    var buf = try makeBuffer(testing.allocator, 20, 3);
    defer buf.deinit();

    var v = DiffViewer{ .content = "-old" };
    v.removed_style = .{ .fg = .magenta, .bold = true };
    v.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 3 });

    const cell = buf.get(0, 0);
    try testing.expectEqual(Color.magenta, cell.?.style.fg.?);
    try testing.expect(cell.?.style.bold);
}

test "render — offset area positions correctly" {
    var buf = try makeBuffer(testing.allocator, 20, 10);
    defer buf.deinit();

    const v = DiffViewer{ .content = "+hi" };
    v.render(&buf, Rect{ .x = 5, .y = 3, .width = 10, .height = 5 });

    // Content should start at (5, 3), not (0, 0)
    try testing.expectEqual(@as(u21, '+'), buf.get(5, 3).?.char);
    try testing.expectEqual(Color.green, buf.get(5, 3).?.style.fg.?);
    // (0, 0) should be blank
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}
