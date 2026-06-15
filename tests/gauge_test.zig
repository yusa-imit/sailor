const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Gauge = sailor.tui.widgets.Gauge;
const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Block = sailor.tui.widgets.Block;
const Color = sailor.tui.Color;

test "Gauge initialization with defaults" {
    const gauge = Gauge{};

    try testing.expectEqual(0.0, gauge.ratio);
    try testing.expect(gauge.label == null);
    try testing.expectEqual(@as(u21, '█'), gauge.filled_char);
    try testing.expectEqual(@as(u21, ' '), gauge.empty_char);
    try testing.expect(gauge.block == null);
}

test "Gauge.withRatio sets ratio" {
    const gauge = (Gauge{}).withRatio(0.75);

    try testing.expectEqual(0.75, gauge.ratio);
}

test "Gauge.withRatio clamps negative to 0.0" {
    const gauge = (Gauge{}).withRatio(-0.5);

    try testing.expectEqual(0.0, gauge.ratio);
}

test "Gauge.withRatio clamps above 1.0 to 1.0" {
    const gauge = (Gauge{}).withRatio(1.5);

    try testing.expectEqual(1.0, gauge.ratio);
}

test "Gauge.withRatio preserves immutability" {
    const original = Gauge{};
    const modified = original.withRatio(0.5);

    try testing.expectEqual(0.0, original.ratio);
    try testing.expectEqual(0.5, modified.ratio);
}

test "Gauge.withPercent converts percentage to ratio" {
    const gauge = (Gauge{}).withPercent(50);

    try testing.expectEqual(0.5, gauge.ratio);
}

test "Gauge.withPercent clamps to 100" {
    const gauge = (Gauge{}).withPercent(150);

    try testing.expectEqual(1.0, gauge.ratio);
}

test "Gauge.withPercent zero percent" {
    const gauge = (Gauge{}).withPercent(0);

    try testing.expectEqual(0.0, gauge.ratio);
}

test "Gauge.withLabel sets label text" {
    const gauge = (Gauge{}).withLabel("50%");

    try testing.expect(gauge.label != null);
    try testing.expectEqualStrings("50%", gauge.label.?);
}

test "Gauge.withFilledChar sets filled character" {
    const gauge = (Gauge{}).withFilledChar('=');

    try testing.expectEqual(@as(u21, '='), gauge.filled_char);
}

test "Gauge.withEmptyChar sets empty character" {
    const gauge = (Gauge{}).withEmptyChar('-');

    try testing.expectEqual(@as(u21, '-'), gauge.empty_char);
}

test "Gauge.withFilledStyle sets filled style" {
    const style = Style{ .fg = Color.green };
    const gauge = (Gauge{}).withFilledStyle(style);

    try testing.expectEqual(Color.green, gauge.filled_style.fg);
}

test "Gauge.withEmptyStyle sets empty style" {
    const style = Style{ .fg = Color.red };
    const gauge = (Gauge{}).withEmptyStyle(style);

    try testing.expectEqual(Color.red, gauge.empty_style.fg);
}

test "Gauge.withLabelStyle sets label style" {
    const style = Style{ .fg = Color.yellow };
    const gauge = (Gauge{}).withLabelStyle(style);

    try testing.expectEqual(Color.yellow, gauge.label_style.fg);
}

test "Gauge.withBlock sets block border" {
    const blk = Block{};
    const gauge = (Gauge{}).withBlock(blk);

    try testing.expect(gauge.block != null);
}

test "Gauge render 0% progress" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.0);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    gauge.render(&buf, area);

    // All should be empty
    for (0..10) |x| {
        try testing.expectEqual(@as(u21, ' '), buf.get(@intCast(x), 0).?.char);
    }
}

test "Gauge render 100% progress" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(1.0);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    gauge.render(&buf, area);

    // All should be filled
    for (0..10) |x| {
        try testing.expectEqual(@as(u21, '█'), buf.get(@intCast(x), 0).?.char);
    }
}

test "Gauge render 50% progress" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.5);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buf, area);

    // First half should be filled
    for (0..10) |x| {
        try testing.expectEqual(@as(u21, '█'), buf.get(@intCast(x), 0).?.char);
    }

    // Second half should be empty
    for (10..20) |x| {
        try testing.expectEqual(@as(u21, ' '), buf.get(@intCast(x), 0).?.char);
    }
}

test "Gauge render 25% progress" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.25);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buf, area);

    // First 5 should be filled (25% of 20 = 5)
    for (0..5) |x| {
        try testing.expectEqual(@as(u21, '█'), buf.get(@intCast(x), 0).?.char);
    }

    // Rest should be empty
    for (5..20) |x| {
        try testing.expectEqual(@as(u21, ' '), buf.get(@intCast(x), 0).?.char);
    }
}

test "Gauge render with custom filled character" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.5).withFilledChar('=');

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    gauge.render(&buf, area);

    // First half should be '='
    for (0..5) |x| {
        try testing.expectEqual(@as(u21, '='), buf.get(@intCast(x), 0).?.char);
    }
}

test "Gauge render with custom empty character" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.5).withEmptyChar('-');

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    gauge.render(&buf, area);

    // Second half should be '-'
    for (5..10) |x| {
        try testing.expectEqual(@as(u21, '-'), buf.get(@intCast(x), 0).?.char);
    }
}

test "Gauge render with both custom characters" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.4).withFilledChar('=').withEmptyChar('-');

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    gauge.render(&buf, area);

    // First 4 should be '='
    for (0..4) |x| {
        try testing.expectEqual(@as(u21, '='), buf.get(@intCast(x), 0).?.char);
    }

    // Rest should be '-'
    for (4..10) |x| {
        try testing.expectEqual(@as(u21, '-'), buf.get(@intCast(x), 0).?.char);
    }
}

test "Gauge render with label centered" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.5).withLabel("50%");

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buf, area);

    // Label should be centered
    // (20 - 3) / 2 = 8
    try testing.expectEqual(@as(u21, '5'), buf.get(8, 0).?.char);
    try testing.expectEqual(@as(u21, '0'), buf.get(9, 0).?.char);
    try testing.expectEqual(@as(u21, '%'), buf.get(10, 0).?.char);
}

test "Gauge render label too long for area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.5).withLabel("Very Long Label");

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };
    gauge.render(&buf, area);

    // Should not render label (too long)
    // But gauge should be rendered
    for (0..2) |x| {
        try testing.expectEqual(@as(u21, '█'), buf.get(@intCast(x), 0).?.char);
    }
}

test "Gauge render with filled style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const filled_style = Style{ .fg = Color.green };
    const gauge = (Gauge{}).withRatio(0.5).withFilledStyle(filled_style);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    gauge.render(&buf, area);

    // Check filled portion has correct style
    try testing.expectEqual(Color.green, buf.get(0, 0).?.style.fg);
}

test "Gauge render with empty style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const empty_style = Style{ .fg = Color.red };
    const gauge = (Gauge{}).withRatio(0.5).withEmptyStyle(empty_style);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    gauge.render(&buf, area);

    // Check empty portion has correct style
    try testing.expectEqual(Color.red, buf.get(5, 0).?.style.fg);
}

test "Gauge render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const blk = (Block{}).withBorders(.all).withTitle("Progress", .top_left);
    const gauge = (Gauge{}).withRatio(0.5).withBlock(blk);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    gauge.render(&buf, area);

    // Block border should be rendered
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);

    // Gauge should be inside block (at y=1)
    try testing.expectEqual(@as(u21, '█'), buf.get(1, 1).?.char);
}

test "Gauge render zero width does nothing" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.5);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    gauge.render(&buf, area);

    // Should not crash
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Gauge render zero height does nothing" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.5);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    gauge.render(&buf, area);

    // Should not crash
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Gauge render with offset area position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.5);

    const area = Rect{ .x = 5, .y = 3, .width = 15, .height = 1 };
    gauge.render(&buf, area);

    // Should render at offset position
    try testing.expectEqual(@as(u21, '█'), buf.get(5, 3).?.char);
}

test "Gauge render fractional progress rounds down" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 7, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.42); // 42% of 7 = 2.94, should be 2

    const area = Rect{ .x = 0, .y = 0, .width = 7, .height = 1 };
    gauge.render(&buf, area);

    // First 2 should be filled
    try testing.expectEqual(@as(u21, '█'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, '█'), buf.get(1, 0).?.char);

    // Rest should be empty
    for (2..7) |x| {
        try testing.expectEqual(@as(u21, ' '), buf.get(@intCast(x), 0).?.char);
    }
}

test "Gauge render with label and styles" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const label_style = Style{ .bold = true };
    const gauge = (Gauge{}).withRatio(0.5).withLabel("50%").withLabelStyle(label_style);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buf, area);

    // Label should be centered at positions 8-10
    try testing.expectEqual(@as(u21, '5'), buf.get(8, 0).?.char);
    try testing.expect(buf.get(8, 0).?.style.bold);
}

test "Gauge builder chain preserves immutability" {
    const original = Gauge{};

    const modified = original
        .withRatio(0.7)
        .withLabel("70%")
        .withFilledChar('=')
        .withEmptyChar('-');

    try testing.expectEqual(0.0, original.ratio);
    try testing.expect(original.label == null);
    try testing.expectEqual(@as(u21, '█'), original.filled_char);
    try testing.expectEqual(@as(u21, ' '), original.empty_char);

    try testing.expectEqual(0.7, modified.ratio);
    try testing.expectEqualStrings("70%", modified.label.?);
    try testing.expectEqual(@as(u21, '='), modified.filled_char);
    try testing.expectEqual(@as(u21, '-'), modified.empty_char);
}

test "Gauge render single width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 1, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(1.0);

    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    gauge.render(&buf, area);

    // Single filled cell at 100%
    try testing.expectEqual(@as(u21, '█'), buf.get(0, 0).?.char);
}

test "Gauge render very small ratio" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 100, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.01); // 1% of 100 = 1

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };
    gauge.render(&buf, area);

    // First 1 should be filled
    try testing.expectEqual(@as(u21, '█'), buf.get(0, 0).?.char);

    // Rest should be empty
    for (1..100) |x| {
        try testing.expectEqual(@as(u21, ' '), buf.get(@intCast(x), 0).?.char);
    }
}

test "Gauge render very large ratio close to 1.0" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 100, 1);
    defer buf.deinit();

    const gauge = (Gauge{}).withRatio(0.99); // 99% of 100 = 99

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };
    gauge.render(&buf, area);

    // First 99 should be filled
    for (0..99) |x| {
        try testing.expectEqual(@as(u21, '█'), buf.get(@intCast(x), 0).?.char);
    }

    // Last one should be empty
    try testing.expectEqual(@as(u21, ' '), buf.get(99, 0).?.char);
}

test "Gauge render label positioned correctly over filled section" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const filled_style = Style{ .fg = Color.green };
    const label_style = Style{ .bold = true };
    const gauge = (Gauge{}).withRatio(0.5).withLabel("50%").withFilledStyle(filled_style).withLabelStyle(label_style);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buf, area);

    // Label is centered at 8-10, which overlaps filled section (0-9)
    // Label should inherit style considerations
    try testing.expectEqual(@as(u21, '5'), buf.get(8, 0).?.char);
}

test "Gauge render preserves buffer state with empty area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    // Mark a cell to verify it's not overwritten
    buf.set(5, 5, .{ .char = 'X', .style = .{} });

    const gauge = (Gauge{}).withRatio(0.5);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    gauge.render(&buf, area);

    // Cell at (5,5) should still be 'X'
    try testing.expectEqual(@as(u21, 'X'), buf.get(5, 5).?.char);
}
