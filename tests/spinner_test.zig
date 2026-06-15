const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Spinner = sailor.tui.widgets.Spinner;
const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Block = sailor.tui.widgets.Block;
const Color = sailor.tui.Color;
const symbols = sailor.tui.symbols;

test "Spinner initialization with defaults" {
    const spinner = Spinner{};

    try testing.expectEqual(@as(usize, 0), spinner.frame);
    try testing.expect(spinner.label == null);
    try testing.expectEqual(symbols.Spinner.braille.len, spinner.frames.len);
    try testing.expect(spinner.block == null);
    try testing.expectEqual(Style{}, spinner.style);
    try testing.expectEqual(Style{}, spinner.label_style);
}

test "Spinner.withFrames sets custom frames" {
    const custom_frames = [_][]const u8{ "-", "\\", "|", "/" };
    const spinner = (Spinner{}).withFrames(&custom_frames);

    try testing.expectEqual(@as(usize, 4), spinner.frames.len);
    try testing.expectEqualStrings("-", spinner.frames[0]);
}

test "Spinner.withFrames preserves immutability" {
    const custom_frames = [_][]const u8{ "a", "b" };
    const original = Spinner{};
    const modified = original.withFrames(&custom_frames);

    try testing.expectEqual(symbols.Spinner.braille.len, original.frames.len);
    try testing.expectEqual(@as(usize, 2), modified.frames.len);
}

test "Spinner.withFrame sets current frame index" {
    const spinner = (Spinner{}).withFrame(3);

    try testing.expectEqual(@as(usize, 3), spinner.frame);
}

test "Spinner.withFrame preserves immutability" {
    const original = Spinner{};
    const modified = original.withFrame(5);

    try testing.expectEqual(@as(usize, 0), original.frame);
    try testing.expectEqual(@as(usize, 5), modified.frame);
}

test "Spinner.withLabel sets label text" {
    const spinner = (Spinner{}).withLabel("Loading");

    try testing.expect(spinner.label != null);
    try testing.expectEqualStrings("Loading", spinner.label.?);
}

test "Spinner.withLabel preserves immutability" {
    const original = Spinner{};
    const modified = original.withLabel("Loading");

    try testing.expect(original.label == null);
    try testing.expectEqualStrings("Loading", modified.label.?);
}

test "Spinner.withStyle sets spinner char style" {
    const style = Style{ .fg = Color.green };
    const spinner = (Spinner{}).withStyle(style);

    try testing.expectEqual(Color.green, spinner.style.fg);
}

test "Spinner.withStyle preserves immutability" {
    const original = Spinner{};
    const style = Style{ .fg = Color.red };
    const modified = original.withStyle(style);

    try testing.expectEqual(Color.red, modified.style.fg);
    try testing.expect(original.style.fg == null);
}

test "Spinner.withLabelStyle sets label text style" {
    const style = Style{ .bold = true };
    const spinner = (Spinner{}).withLabelStyle(style);

    try testing.expect(spinner.label_style.bold);
}

test "Spinner.withLabelStyle preserves immutability" {
    const original = Spinner{};
    const style = Style{ .bold = true };
    const modified = original.withLabelStyle(style);

    try testing.expect(modified.label_style.bold);
    try testing.expect(!original.label_style.bold);
}

test "Spinner.withBlock sets block border" {
    const blk = Block{};
    const spinner = (Spinner{}).withBlock(blk);

    try testing.expect(spinner.block != null);
}

test "Spinner.withBlock preserves immutability" {
    const original = Spinner{};
    const blk = Block{};
    const modified = original.withBlock(blk);

    try testing.expect(original.block == null);
    try testing.expect(modified.block != null);
}

test "Spinner.currentFrame returns frames[frame % frames.len]" {
    const spinner = (Spinner{}).withFrame(0);

    const frame = spinner.currentFrame();
    try testing.expectEqualStrings(symbols.Spinner.braille[0], frame);
}

test "Spinner.currentFrame wraps around correctly" {
    const spinner = (Spinner{}).withFrame(8).withFrames(&symbols.Spinner.braille);

    const frame = spinner.currentFrame();
    try testing.expectEqualStrings(symbols.Spinner.braille[0], frame);
}

test "Spinner.currentFrame with custom frames" {
    const custom = [_][]const u8{ "a", "b", "c" };
    const spinner = (Spinner{}).withFrames(&custom).withFrame(2);

    const frame = spinner.currentFrame();
    try testing.expectEqualStrings("c", frame);
}

test "Spinner.currentFrame wraps custom frames" {
    const custom = [_][]const u8{ "a", "b" };
    const spinner = (Spinner{}).withFrames(&custom).withFrame(5);

    const frame = spinner.currentFrame();
    try testing.expectEqualStrings("b", frame);
}

test "Spinner.tick increments frame" {
    const spinner = (Spinner{}).withFrame(0);
    const ticked = spinner.tick();

    try testing.expectEqual(@as(usize, 1), ticked.frame);
}

test "Spinner.tick preserves immutability" {
    const original = (Spinner{}).withFrame(0);
    const ticked = original.tick();

    try testing.expectEqual(@as(usize, 0), original.frame);
    try testing.expectEqual(@as(usize, 1), ticked.frame);
}

test "Spinner.tick wraps via modulo in currentFrame" {
    const spinner = (Spinner{}).withFrame(7).withFrames(&symbols.Spinner.braille);
    const ticked = spinner.tick();

    try testing.expectEqual(@as(usize, 8), ticked.frame);
    // currentFrame should wrap it via modulo
    const frame = ticked.currentFrame();
    try testing.expectEqualStrings(symbols.Spinner.braille[0], frame);
}

test "Spinner.tick preserves label and styles" {
    const spinner = (Spinner{})
        .withLabel("Loading")
        .withStyle(Style{ .fg = Color.green })
        .withLabelStyle(Style{ .bold = true });

    const ticked = spinner.tick();

    try testing.expectEqualStrings("Loading", ticked.label.?);
    try testing.expectEqual(Color.green, ticked.style.fg);
    try testing.expect(ticked.label_style.bold);
}

test "Spinner builder chain preserves immutability" {
    const original = Spinner{};
    const modified = original
        .withFrame(3)
        .withLabel("Work")
        .withStyle(Style{ .fg = Color.blue });

    try testing.expectEqual(@as(usize, 0), original.frame);
    try testing.expect(original.label == null);
    try testing.expect(original.style.fg == null);

    try testing.expectEqual(@as(usize, 3), modified.frame);
    try testing.expectEqualStrings("Work", modified.label.?);
    try testing.expectEqual(Color.blue, modified.style.fg);
}

test "Spinner render frame at x=0, y=0" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 1);
    defer buf.deinit();

    const spinner = Spinner{};
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };
    spinner.render(&buf, area);

    // First cell should contain the spinner frame character
    const cell = buf.get(0, 0).?;
    const expected_char = std.unicode.utf8Decode(symbols.Spinner.braille[0]) catch ' ';
    try testing.expectEqual(expected_char, cell.char);
}

test "Spinner render at offset position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const spinner = Spinner{};
    const area = Rect{ .x = 5, .y = 3, .width = 10, .height = 1 };
    spinner.render(&buf, area);

    // Spinner frame should be at the offset position
    const cell = buf.get(5, 3).?;
    const expected_char = std.unicode.utf8Decode(symbols.Spinner.braille[0]) catch ' ';
    try testing.expectEqual(expected_char, cell.char);
}

test "Spinner render with label adds space and text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const spinner = (Spinner{}).withLabel("Loading");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    spinner.render(&buf, area);

    // Position 0 should have spinner char
    const spinner_cell = buf.get(0, 0).?;
    const expected_spinner = std.unicode.utf8Decode(symbols.Spinner.braille[0]) catch ' ';
    try testing.expectEqual(expected_spinner, spinner_cell.char);

    // Position 1 should have space
    const space_cell = buf.get(1, 0).?;
    try testing.expectEqual(@as(u21, ' '), space_cell.char);

    // Position 2 onwards should have label
    const label_cell = buf.get(2, 0).?;
    try testing.expectEqual(@as(u21, 'L'), label_cell.char);
}

test "Spinner render label truncation on narrow area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 1);
    defer buf.deinit();

    const spinner = (Spinner{}).withLabel("Loading");
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };
    spinner.render(&buf, area);

    // Spinner char should always be rendered
    const spinner_cell = buf.get(0, 0).?;
    const expected_spinner = std.unicode.utf8Decode(symbols.Spinner.braille[0]) catch ' ';
    try testing.expectEqual(expected_spinner, spinner_cell.char);
}

test "Spinner render applies spinner char style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const style = Style{ .fg = Color.green };
    const spinner = (Spinner{}).withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    spinner.render(&buf, area);

    const cell = buf.get(0, 0).?;
    try testing.expectEqual(Color.green, cell.style.fg);
}

test "Spinner render applies label style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const label_style = Style{ .bold = true };
    const spinner = (Spinner{}).withLabel("Go").withLabelStyle(label_style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    spinner.render(&buf, area);

    // Label character at position 2 should have bold style
    const cell = buf.get(2, 0).?;
    try testing.expect(cell.style.bold);
}

test "Spinner render with custom frames" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const custom = [_][]const u8{ "-", "\\", "|", "/" };
    const spinner = (Spinner{}).withFrames(&custom).withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    spinner.render(&buf, area);

    // Should render '-' at position 0
    const cell = buf.get(0, 0).?;
    try testing.expectEqual(@as(u21, '-'), cell.char);
}

test "Spinner render at different frame" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const spinner = (Spinner{}).withFrame(3);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    spinner.render(&buf, area);

    // Should render braille[3]
    const frame_str = symbols.Spinner.braille[3];
    const cell = buf.get(0, 0).?;
    const expected_char = std.unicode.utf8Decode(frame_str) catch ' ';
    try testing.expectEqual(expected_char, cell.char);
}

test "Spinner render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const blk = (Block{}).withBorders(.all);
    const spinner = (Spinner{}).withBlock(blk);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    spinner.render(&buf, area);

    // Block border should be rendered
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, '│'), buf.get(0, 1).?.char);
    try testing.expectEqual(@as(u21, '└'), buf.get(0, 2).?.char);

    // Spinner should be inside block
    // Usually at (1, 1) after block border
    const spinner_cell = buf.get(1, 1).?;
    const expected_spinner = std.unicode.utf8Decode(symbols.Spinner.braille[0]) catch ' ';
    try testing.expectEqual(expected_spinner, spinner_cell.char);
}

test "Spinner render zero width does nothing" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    // Pre-fill with marker
    buf.set(0, 0, .{ .char = 'X', .style = .{} });

    const spinner = Spinner{};
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    spinner.render(&buf, area);

    // Should not crash; buffer should remain unchanged
    try testing.expectEqual(@as(u21, 'X'), buf.get(0, 0).?.char);
}

test "Spinner render zero height does nothing" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    // Pre-fill with marker
    buf.set(0, 0, .{ .char = 'X', .style = .{} });

    const spinner = Spinner{};
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    spinner.render(&buf, area);

    // Should not crash
    try testing.expectEqual(@as(u21, 'X'), buf.get(0, 0).?.char);
}

test "Spinner render single width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 1, 1);
    defer buf.deinit();

    const spinner = Spinner{};
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    spinner.render(&buf, area);

    // Single cell should have spinner frame
    const cell = buf.get(0, 0).?;
    const expected_char = std.unicode.utf8Decode(symbols.Spinner.braille[0]) catch ' ';
    try testing.expectEqual(expected_char, cell.char);
}

test "Spinner render label at offset area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    const spinner = (Spinner{}).withLabel("Work");
    const area = Rect{ .x = 10, .y = 5, .width = 15, .height = 1 };
    spinner.render(&buf, area);

    // Spinner frame at (10, 5)
    const spinner_cell = buf.get(10, 5).?;
    const expected_spinner = std.unicode.utf8Decode(symbols.Spinner.braille[0]) catch ' ';
    try testing.expectEqual(expected_spinner, spinner_cell.char);

    // Space at (11, 5)
    const space_cell = buf.get(11, 5).?;
    try testing.expectEqual(@as(u21, ' '), space_cell.char);

    // Label 'W' at (12, 5)
    const label_cell = buf.get(12, 5).?;
    try testing.expectEqual(@as(u21, 'W'), label_cell.char);
}

test "Spinner render empty label" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const spinner = (Spinner{}).withLabel("");
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    spinner.render(&buf, area);

    // Spinner char should still be rendered
    const spinner_cell = buf.get(0, 0).?;
    const expected_spinner = std.unicode.utf8Decode(symbols.Spinner.braille[0]) catch ' ';
    try testing.expectEqual(expected_spinner, spinner_cell.char);

    // Position 1 should have space (or not, depending on implementation)
    // We just ensure it doesn't crash
}

test "Spinner render tall area with single row spinner" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const spinner = Spinner{};
    const area = Rect{ .x = 0, .y = 2, .width = 10, .height = 5 };
    spinner.render(&buf, area);

    // Spinner should render at top-left of area, which is y=2
    const spinner_cell = buf.get(0, 2).?;
    const expected_spinner = std.unicode.utf8Decode(symbols.Spinner.braille[0]) catch ' ';
    try testing.expectEqual(expected_spinner, spinner_cell.char);
}

test "Spinner render frame styles independently" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const spinner_style = Style{ .fg = Color.red };
    const label_style = Style{ .fg = Color.blue };
    const spinner = (Spinner{})
        .withLabel("Go")
        .withStyle(spinner_style)
        .withLabelStyle(label_style);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    spinner.render(&buf, area);

    // Spinner char at position 0 should have red
    const spinner_cell = buf.get(0, 0).?;
    try testing.expectEqual(Color.red, spinner_cell.style.fg);

    // Label char at position 2 should have blue
    const label_cell = buf.get(2, 0).?;
    try testing.expectEqual(Color.blue, label_cell.style.fg);
}

test "Spinner tick sequence" {
    var spinner = Spinner{};

    // Verify tick sequence progresses frame
    for (0..4) |i| {
        try testing.expectEqual(i, spinner.frame);
        spinner = spinner.tick();
    }
    try testing.expectEqual(@as(usize, 4), spinner.frame);
}

test "Spinner currentFrame with frame 0" {
    const spinner = (Spinner{}).withFrame(0);
    const frame = spinner.currentFrame();
    try testing.expectEqualStrings(symbols.Spinner.braille[0], frame);
}

test "Spinner currentFrame with last frame" {
    const last_idx = symbols.Spinner.braille.len - 1;
    const spinner = (Spinner{}).withFrame(last_idx);
    const frame = spinner.currentFrame();
    try testing.expectEqualStrings(symbols.Spinner.braille[last_idx], frame);
}

test "Spinner render label only if area wide enough" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 3, 1);
    defer buf.deinit();

    const spinner = (Spinner{}).withLabel("Hi");
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 1 };
    spinner.render(&buf, area);

    // Position 0: spinner frame
    // Position 1: space
    // Position 2: 'H'
    try testing.expectEqual(@as(u21, 'H'), buf.get(2, 0).?.char);
}
