//! Fluent Span and Line Builder Tests — v1.22.0
//!
//! Tests for SpanBuilder and LineBuilder fluent APIs that enable
//! composing styled text through method chaining.
//!
//! Validation covered:
//! - SpanBuilder basic text and modifier chaining
//! - SpanBuilder color operations (fg, bg, indexed, rgb)
//! - SpanBuilder style merging and overrides
//! - SpanBuilder rendering with ANSI codes
//! - LineBuilder single and multiple spans
//! - LineBuilder mixed styled and unstyled content
//! - LineBuilder rendering verification
//! - Integration with existing Span/Line rendering
//! - Edge cases (empty text, repeated modifiers, null colors)

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const Color = sailor.tui.Color;
const Style = sailor.tui.Style;
const Span = sailor.tui.Span;
const Line = sailor.tui.Line;
const SpanBuilder = sailor.tui.SpanBuilder;
const LineBuilder = sailor.tui.LineBuilder;

// ============================================================================
// SpanBuilder — Basic Usage Tests
// ============================================================================

test "SpanBuilder: text only" {
    var builder = SpanBuilder.init();
    _ = builder.text("hello");
    const span = builder.build();

    try testing.expectEqualStrings("hello", span.content);
    try testing.expectEqual(Style.default, span.style);
}

test "SpanBuilder: empty text" {
    var builder = SpanBuilder.init();
    _ = builder.text("");
    const span = builder.build();

    try testing.expectEqualStrings("", span.content);
    try testing.expectEqual(Style.default, span.style);
}

test "SpanBuilder: text with single modifier (bold)" {
    var builder = SpanBuilder.init();
    _ = builder.text("bold text").bold();
    const span = builder.build();

    try testing.expectEqualStrings("bold text", span.content);
    try testing.expect(span.style.bold);
    try testing.expect(!span.style.italic);
    try testing.expect(!span.style.underline);
}

test "SpanBuilder: text with single modifier (italic)" {
    var builder = SpanBuilder.init();
    _ = builder.text("italic text").italic();
    const span = builder.build();

    try testing.expectEqualStrings("italic text", span.content);
    try testing.expect(span.style.italic);
    try testing.expect(!span.style.bold);
}

test "SpanBuilder: text with single modifier (underline)" {
    var builder = SpanBuilder.init();
    _ = builder.text("underline text").underline();
    const span = builder.build();

    try testing.expectEqualStrings("underline text", span.content);
    try testing.expect(span.style.underline);
}

test "SpanBuilder: text with single modifier (dim)" {
    var builder = SpanBuilder.init();
    _ = builder.text("dim text").dim();
    const span = builder.build();

    try testing.expectEqualStrings("dim text", span.content);
    try testing.expect(span.style.dim);
}

test "SpanBuilder: text with single modifier (strikethrough)" {
    var builder = SpanBuilder.init();
    _ = builder.text("strikethrough text").strikethrough();
    const span = builder.build();

    try testing.expectEqualStrings("strikethrough text", span.content);
    try testing.expect(span.style.strikethrough);
}

// ============================================================================
// SpanBuilder — Method Chaining Tests
// ============================================================================

test "SpanBuilder: chaining bold and italic" {
    var builder = SpanBuilder.init();
    _ = builder.text("styled").bold().italic();
    const span = builder.build();

    try testing.expectEqualStrings("styled", span.content);
    try testing.expect(span.style.bold);
    try testing.expect(span.style.italic);
}

test "SpanBuilder: chaining bold, italic, underline" {
    var builder = SpanBuilder.init();
    _ = builder.text("triple").bold().italic().underline();
    const span = builder.build();

    try testing.expectEqualStrings("triple", span.content);
    try testing.expect(span.style.bold);
    try testing.expect(span.style.italic);
    try testing.expect(span.style.underline);
}

test "SpanBuilder: chaining all modifiers" {
    var builder = SpanBuilder.init();
    _ = builder.text("all").bold().dim().italic().underline().strikethrough();
    const span = builder.build();

    try testing.expectEqualStrings("all", span.content);
    try testing.expect(span.style.bold);
    try testing.expect(span.style.dim);
    try testing.expect(span.style.italic);
    try testing.expect(span.style.underline);
    try testing.expect(span.style.strikethrough);
}

test "SpanBuilder: repeated modifiers (idempotent)" {
    var builder = SpanBuilder.init();
    _ = builder.text("text").bold().bold().bold();
    const span = builder.build();

    try testing.expectEqualStrings("text", span.content);
    try testing.expect(span.style.bold);
}

// ============================================================================
// SpanBuilder — Color Tests (Foreground)
// ============================================================================

test "SpanBuilder: foreground color (named)" {
    var builder = SpanBuilder.init();
    _ = builder.text("red").fg(.red);
    const span = builder.build();

    try testing.expectEqualStrings("red", span.content);
    const expected_color: Color = .red;
    try testing.expectEqual(expected_color, span.style.fg.?);
    try testing.expectEqual(@as(?Color, null), span.style.bg);
}

test "SpanBuilder: foreground color (indexed)" {
    var builder = SpanBuilder.init();
    _ = builder.text("indexed").fg(Color{ .indexed = 208 });
    const span = builder.build();

    try testing.expectEqualStrings("indexed", span.content);
    try testing.expectEqual(@as(u8, 208), span.style.fg.?.indexed);
}

test "SpanBuilder: foreground color (rgb)" {
    var builder = SpanBuilder.init();
    _ = builder.text("rgb").fg(Color{ .rgb = .{ .r = 255, .g = 128, .b = 0 } });
    const span = builder.build();

    try testing.expectEqualStrings("rgb", span.content);
    const rgb = span.style.fg.?.rgb;
    try testing.expectEqual(255, rgb.r);
    try testing.expectEqual(128, rgb.g);
    try testing.expectEqual(0, rgb.b);
}

test "SpanBuilder: foreground color reset" {
    var builder = SpanBuilder.init();
    _ = builder.text("reset").fg(.reset);
    const span = builder.build();

    try testing.expectEqualStrings("reset", span.content);
    const expected_color: Color = .reset;
    try testing.expectEqual(expected_color, span.style.fg.?);
}

// ============================================================================
// SpanBuilder — Color Tests (Background)
// ============================================================================

test "SpanBuilder: background color (named)" {
    var builder = SpanBuilder.init();
    _ = builder.text("blue bg").bg(.blue);
    const span = builder.build();

    try testing.expectEqualStrings("blue bg", span.content);
    const expected_color: Color = .blue;
    try testing.expectEqual(expected_color, span.style.bg.?);
}

test "SpanBuilder: background color (indexed)" {
    var builder = SpanBuilder.init();
    _ = builder.text("indexed bg").bg(Color{ .indexed = 42 });
    const span = builder.build();

    try testing.expectEqualStrings("indexed bg", span.content);
    try testing.expectEqual(@as(u8, 42), span.style.bg.?.indexed);
}

test "SpanBuilder: background color (rgb)" {
    var builder = SpanBuilder.init();
    _ = builder.text("rgb bg").bg(Color{ .rgb = .{ .r = 100, .g = 150, .b = 200 } });
    const span = builder.build();

    try testing.expectEqualStrings("rgb bg", span.content);
    const rgb = span.style.bg.?.rgb;
    try testing.expectEqual(100, rgb.r);
    try testing.expectEqual(150, rgb.g);
    try testing.expectEqual(200, rgb.b);
}

// ============================================================================
// SpanBuilder — Color Chaining Tests
// ============================================================================

test "SpanBuilder: foreground and background colors" {
    var builder = SpanBuilder.init();
    _ = builder.text("colored").fg(.green).bg(.black);
    const span = builder.build();

    try testing.expectEqualStrings("colored", span.content);
    const expected_fg: Color = .green;
    const expected_bg: Color = .black;
    try testing.expectEqual(expected_fg, span.style.fg.?);
    try testing.expectEqual(expected_bg, span.style.bg.?);
}

test "SpanBuilder: colors with modifiers" {
    var builder = SpanBuilder.init();
    _ = builder.text("full").fg(.red).bg(.white).bold().italic();
    const span = builder.build();

    try testing.expectEqualStrings("full", span.content);
    const expected_fg: Color = .red;
    const expected_bg: Color = .white;
    try testing.expectEqual(expected_fg, span.style.fg.?);
    try testing.expectEqual(expected_bg, span.style.bg.?);
    try testing.expect(span.style.bold);
    try testing.expect(span.style.italic);
}

test "SpanBuilder: color override" {
    var builder = SpanBuilder.init();
    _ = builder.text("override").fg(.red).fg(.blue);
    const span = builder.build();

    try testing.expectEqualStrings("override", span.content);
    const expected_color: Color = .blue;
    try testing.expectEqual(expected_color, span.style.fg.?);
}

// ============================================================================
// SpanBuilder — Style Merging Tests
// ============================================================================

test "SpanBuilder: apply complete Style struct" {
    var builder = SpanBuilder.init();
    const style = Style{
        .fg = .yellow,
        .bg = .black,
        .bold = true,
        .italic = true,
    };
    _ = builder.text("styled").style(style);
    const span = builder.build();

    try testing.expectEqualStrings("styled", span.content);
    const expected_fg: Color = .yellow;
    const expected_bg: Color = .black;
    try testing.expectEqual(expected_fg, span.style.fg.?);
    try testing.expectEqual(expected_bg, span.style.bg.?);
    try testing.expect(span.style.bold);
    try testing.expect(span.style.italic);
}

test "SpanBuilder: style then modifier (modifier overrides)" {
    var builder = SpanBuilder.init();
    const base_style = Style{ .bold = true, .italic = false };
    _ = builder.text("merge").style(base_style).italic();
    const span = builder.build();

    try testing.expectEqualStrings("merge", span.content);
    try testing.expect(span.style.bold);
    try testing.expect(span.style.italic);
}

test "SpanBuilder: modifier then style (style merges)" {
    var builder = SpanBuilder.init();
    const overlay_style = Style{ .fg = .red };
    _ = builder.text("order").bold().style(overlay_style);
    const span = builder.build();

    try testing.expectEqualStrings("order", span.content);
    try testing.expect(span.style.bold);
    const expected_color: Color = .red;
    try testing.expectEqual(expected_color, span.style.fg.?);
}

// ============================================================================
// SpanBuilder — Rendering Tests
// ============================================================================

test "SpanBuilder: render bold text" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    var builder = SpanBuilder.init();
    _ = builder.text("bold").bold();
    const span = builder.build();

    try span.render(writer);
    try testing.expectEqualStrings("\x1b[1mbold\x1b[0m", fbs.getWritten());
}

test "SpanBuilder: render colored text" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    var builder = SpanBuilder.init();
    _ = builder.text("red").fg(.red);
    const span = builder.build();

    try span.render(writer);
    try testing.expectEqualStrings("\x1b[31mred\x1b[0m", fbs.getWritten());
}

test "SpanBuilder: render with background color" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    var builder = SpanBuilder.init();
    _ = builder.text("bg").bg(.blue);
    const span = builder.build();

    try span.render(writer);
    try testing.expectEqualStrings("\x1b[44mbg\x1b[0m", fbs.getWritten());
}

test "SpanBuilder: render full styling (color + modifiers)" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    var builder = SpanBuilder.init();
    _ = builder.text("full").fg(.red).bg(.white).bold().italic().underline();
    const span = builder.build();

    try span.render(writer);
    const expected = "\x1b[31m\x1b[47m\x1b[1m\x1b[3m\x1b[4mfull\x1b[0m";
    try testing.expectEqualStrings(expected, fbs.getWritten());
}

test "SpanBuilder: render unstyled text (no ANSI codes)" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    var builder = SpanBuilder.init();
    _ = builder.text("plain");
    const span = builder.build();

    try span.render(writer);
    try testing.expectEqualStrings("plain", fbs.getWritten());
}

// ============================================================================
// LineBuilder — Basic Tests
// ============================================================================

test "LineBuilder: single raw span" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.raw("hello");
    const line = builder.build();

    try testing.expectEqual(1, line.spans.len);
    try testing.expectEqualStrings("hello", line.spans[0].content);
}

test "LineBuilder: single styled span" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    const style = Style{ .bold = true };
    _ = builder.text("bold", style);
    const line = builder.build();

    try testing.expectEqual(1, line.spans.len);
    try testing.expectEqualStrings("bold", line.spans[0].content);
    try testing.expect(line.spans[0].style.bold);
}

test "LineBuilder: add pre-built span" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    var span_builder = SpanBuilder.init();
    _ = span_builder.text("styled").bold().fg(.red);
    const span = span_builder.build();

    _ = builder.span(span);
    const line = builder.build();

    try testing.expectEqual(1, line.spans.len);
    try testing.expectEqualStrings("styled", line.spans[0].content);
    try testing.expect(line.spans[0].style.bold);
    const expected_color: Color = .red;
    try testing.expectEqual(expected_color, line.spans[0].style.fg.?);
}

// ============================================================================
// LineBuilder — Multiple Spans Tests
// ============================================================================

test "LineBuilder: multiple raw spans" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.raw("hello");
    _ = builder.raw(" ");
    _ = builder.raw("world");
    const line = builder.build();

    try testing.expectEqual(3, line.spans.len);
    try testing.expectEqualStrings("hello", line.spans[0].content);
    try testing.expectEqualStrings(" ", line.spans[1].content);
    try testing.expectEqualStrings("world", line.spans[2].content);
}

test "LineBuilder: multiple styled spans" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.text("red", .{ .fg = .red });
    _ = builder.text("green", .{ .fg = .green });
    _ = builder.text("blue", .{ .fg = .blue });
    const line = builder.build();

    try testing.expectEqual(3, line.spans.len);
    const expected_red: Color = .red;
    const expected_green: Color = .green;
    const expected_blue: Color = .blue;
    try testing.expectEqual(expected_red, line.spans[0].style.fg.?);
    try testing.expectEqual(expected_green, line.spans[1].style.fg.?);
    try testing.expectEqual(expected_blue, line.spans[2].style.fg.?);
}

test "LineBuilder: mixed raw and styled" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.raw("Normal ");
    _ = builder.text("bold", .{ .bold = true });
    _ = builder.raw(" normal");
    const line = builder.build();

    try testing.expectEqual(3, line.spans.len);
    try testing.expectEqualStrings("Normal ", line.spans[0].content);
    try testing.expect(!line.spans[0].style.bold);
    try testing.expectEqualStrings("bold", line.spans[1].content);
    try testing.expect(line.spans[1].style.bold);
    try testing.expectEqualStrings(" normal", line.spans[2].content);
    try testing.expect(!line.spans[2].style.bold);
}

test "LineBuilder: mixed pre-built and raw" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    var sb = SpanBuilder.init();
    _ = sb.text("span1").italic();
    _ = builder.span(sb.build());

    _ = builder.raw(" text");

    var sb2 = SpanBuilder.init();
    _ = sb2.text("span2").underline();
    _ = builder.span(sb2.build());

    const line = builder.build();

    try testing.expectEqual(3, line.spans.len);
    try testing.expect(line.spans[0].style.italic);
    try testing.expect(!line.spans[1].style.italic);
    try testing.expect(line.spans[2].style.underline);
}

// ============================================================================
// LineBuilder — Rendering Tests
// ============================================================================

test "LineBuilder: render single span" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.raw("hello");
    const line = builder.build();

    try line.render(writer);
    try testing.expectEqualStrings("hello", fbs.getWritten());
}

test "LineBuilder: render multiple spans" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.text("Hello", .{ .fg = .red });
    _ = builder.raw(" ");
    _ = builder.text("world", .{ .fg = .blue, .bold = true });
    const line = builder.build();

    try line.render(writer);
    const expected = "\x1b[31mHello\x1b[0m \x1b[34m\x1b[1mworld\x1b[0m";
    try testing.expectEqualStrings(expected, fbs.getWritten());
}

test "LineBuilder: render complex formatting" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.text("Error", .{ .fg = .red, .bold = true });
    _ = builder.raw(": ");
    _ = builder.text("operation failed", .{ .fg = .yellow });
    const line = builder.build();

    try line.render(writer);
    const expected = "\x1b[31m\x1b[1mError\x1b[0m: \x1b[33moperation failed\x1b[0m";
    try testing.expectEqualStrings(expected, fbs.getWritten());
}

// ============================================================================
// LineBuilder — Owned Build Tests (with allocator)
// ============================================================================

test "LineBuilder: buildOwned allocates memory" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.raw("hello");
    _ = builder.raw(" ");
    _ = builder.raw("world");

    const line = try builder.buildOwned();
    defer allocator.free(line.spans);

    try testing.expectEqual(3, line.spans.len);
    try testing.expectEqualStrings("hello", line.spans[0].content);
}

test "LineBuilder: buildOwned with complex spans" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.text("red", .{ .fg = .red });
    _ = builder.raw(" + ");
    _ = builder.text("blue", .{ .fg = .blue });

    const line = try builder.buildOwned();
    defer allocator.free(line.spans);

    try testing.expectEqual(3, line.spans.len);
    const expected_red: Color = .red;
    const expected_blue: Color = .blue;
    try testing.expectEqual(expected_red, line.spans[0].style.fg.?);
    try testing.expectEqual(expected_blue, line.spans[2].style.fg.?);
}

// ============================================================================
// Integration Tests — SpanBuilder Output in LineBuilder
// ============================================================================

test "integration: build span then add to line" {
    const allocator = testing.allocator;

    var span_builder = SpanBuilder.init();
    _ = span_builder.text("styled").bold().fg(.red);
    const span = span_builder.build();

    var line_builder = LineBuilder.init(allocator);
    defer line_builder.deinit();
    _ = line_builder.span(span);
    _ = line_builder.raw(" text");

    const line = line_builder.build();

    try testing.expectEqual(2, line.spans.len);
    try testing.expect(line.spans[0].style.bold);
    const expected_color: Color = .red;
    try testing.expectEqual(expected_color, line.spans[0].style.fg.?);
}

test "integration: multiple builders in single line" {
    const allocator = testing.allocator;

    var sb1 = SpanBuilder.init();
    _ = sb1.text("Hello").fg(.red).bold();

    var sb2 = SpanBuilder.init();
    _ = sb2.text("world").fg(.blue).italic();

    var line_builder = LineBuilder.init(allocator);
    defer line_builder.deinit();
    _ = line_builder.span(sb1.build());
    _ = line_builder.raw(" ");
    _ = line_builder.span(sb2.build());

    const line = line_builder.build();

    try testing.expectEqual(3, line.spans.len);
    try testing.expect(line.spans[0].style.bold);
    try testing.expect(line.spans[2].style.italic);
}

test "integration: render complete styled line" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const allocator = testing.allocator;

    var sb = SpanBuilder.init();
    _ = sb.text("Task").fg(.green).bold();

    var lb = LineBuilder.init(allocator);
    defer lb.deinit();
    _ = lb.span(sb.build());
    _ = lb.raw(": ");
    _ = lb.text("Complete", .{ .fg = .cyan });

    const line = lb.build();
    try line.render(writer);

    const expected = "\x1b[32m\x1b[1mTask\x1b[0m: \x1b[36mComplete\x1b[0m";
    try testing.expectEqualStrings(expected, fbs.getWritten());
}

// ============================================================================
// Edge Cases
// ============================================================================

test "edge case: empty LineBuilder" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    const line = builder.build();

    try testing.expectEqual(0, line.spans.len);
}

test "edge case: LineBuilder with only whitespace" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.raw("   ");
    const line = builder.build();

    try testing.expectEqual(1, line.spans.len);
    try testing.expectEqualStrings("   ", line.spans[0].content);
}

test "edge case: SpanBuilder reset color" {
    var builder = SpanBuilder.init();
    _ = builder.text("text").fg(.red).fg(.reset);
    const span = builder.build();

    const expected_color: Color = .reset;
    try testing.expectEqual(expected_color, span.style.fg.?);
}

test "edge case: LineBuilder with many spans" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = builder.raw("x");
    }

    const line = builder.build();
    try testing.expectEqual(100, line.spans.len);
}

test "edge case: SpanBuilder with very long text" {
    var builder = SpanBuilder.init();
    const long_text = "abcdefghijklmnopqrstuvwxyz" ** 10; // 260 chars
    _ = builder.text(long_text).bold();
    const span = builder.build();

    try testing.expectEqualStrings(long_text, span.content);
    try testing.expect(span.style.bold);
}

test "edge case: LineBuilder width calculation" {
    const allocator = testing.allocator;
    var builder = LineBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.raw("hello");
    _ = builder.raw(" ");
    _ = builder.raw("world");

    const line = builder.build();
    try testing.expectEqual(11, line.width());
}

// ============================================================================
// Bright Colors Tests
// ============================================================================

test "SpanBuilder: bright foreground colors" {
    var builder = SpanBuilder.init();
    _ = builder.text("bright red").fg(.bright_red);
    const span = builder.build();

    const expected_color: Color = .bright_red;
    try testing.expectEqual(expected_color, span.style.fg.?);
}

test "SpanBuilder: bright background colors" {
    var builder = SpanBuilder.init();
    _ = builder.text("bright bg").bg(.bright_yellow);
    const span = builder.build();

    const expected_color: Color = .bright_yellow;
    try testing.expectEqual(expected_color, span.style.bg.?);
}

test "SpanBuilder: render bright colors" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    var builder = SpanBuilder.init();
    _ = builder.text("bright").fg(.bright_green);
    const span = builder.build();

    try span.render(writer);
    try testing.expectEqualStrings("\x1b[92mbright\x1b[0m", fbs.getWritten());
}

// ============================================================================
// Reverse and Blink Tests
// ============================================================================

test "SpanBuilder: reverse modifier" {
    var builder = SpanBuilder.init();
    _ = builder.text("reversed").reverse();
    const span = builder.build();

    try testing.expect(span.style.reverse);
}

test "SpanBuilder: blink modifier" {
    var builder = SpanBuilder.init();
    _ = builder.text("blinking").blink();
    const span = builder.build();

    try testing.expect(span.style.blink);
}

test "SpanBuilder: render reverse and blink" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    var builder = SpanBuilder.init();
    _ = builder.text("effects").reverse().blink();
    const span = builder.build();

    try span.render(writer);
    const expected = "\x1b[7m\x1b[5meffects\x1b[0m";
    try testing.expectEqualStrings(expected, fbs.getWritten());
}
