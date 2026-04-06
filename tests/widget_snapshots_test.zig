//! Widget Snapshot Testing
//!
//! Comprehensive snapshot tests for all widgets to ensure rendering output
//! matches expected visual appearance. Uses MockTerminal for TTY-free testing.
//!
//! Note: This tests basic rendering behavior and key visual elements rather than
//! exact character-by-character output, as widget rendering details may evolve.

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

const MockTerminal = sailor.tui.test_utils.MockTerminal;
const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Line = sailor.tui.Line;
const Span = sailor.tui.Span;
const BoxSet = sailor.tui.BoxSet;

// Widget imports
const Block = sailor.tui.widgets.Block;
const Borders = sailor.tui.widgets.Borders;
const Paragraph = sailor.tui.widgets.Paragraph;
const List = sailor.tui.widgets.List;
const Table = sailor.tui.widgets.Table;
const Column = sailor.tui.widgets.Column;
const Gauge = sailor.tui.widgets.Gauge;
const Sparkline = sailor.tui.widgets.Sparkline;

// ============================================================================
// Block Widget Snapshots
// ============================================================================

test "Block: renders border corners correctly" {
    var term = try MockTerminal.init(testing.allocator, 12, 5);
    defer term.deinit();

    const block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Test", .top_left);

    block.render(&term.current, term.size());

    // Check corners
    try testing.expectEqual('┌', term.getChar(0, 0).?);
    try testing.expectEqual('┐', term.getChar(11, 0).?);
    try testing.expectEqual('└', term.getChar(0, 4).?);
    try testing.expectEqual('┘', term.getChar(11, 4).?);

    // Check title appears
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Test") != null);
}

test "Block: no borders means title doesn't render" {
    var term = try MockTerminal.init(testing.allocator, 8, 3);
    defer term.deinit();

    const block = (Block{})
        .withBorders(Borders.none)
        .withTitle("Plain", .top_left);

    block.render(&term.current, term.size());

    // With no borders, title has nowhere to render (needs top border)
    // So terminal should be empty
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    // No border corners
    try testing.expect(term.getChar(0, 0).? != '┌');

    // Terminal should be all spaces/newlines
    for (snapshot) |char| {
        if (char != ' ' and char != '\n') {
            return error.TestFailed;
        }
    }
}

test "Block: thick border set" {
    var term = try MockTerminal.init(testing.allocator, 10, 4);
    defer term.deinit();

    const block = (Block{})
        .withBorders(Borders.all)
        .withBorderSet(BoxSet.thick)
        .withTitle("Thick", .top_left);

    block.render(&term.current, term.size());

    // Check thick corners
    try testing.expectEqual('┏', term.getChar(0, 0).?);
    try testing.expectEqual('┓', term.getChar(9, 0).?);
    try testing.expectEqual('┗', term.getChar(0, 3).?);
    try testing.expectEqual('┛', term.getChar(9, 3).?);
}

test "Block: rounded border set" {
    var term = try MockTerminal.init(testing.allocator, 10, 4);
    defer term.deinit();

    const block = (Block{})
        .withBorders(Borders.all)
        .withBorderSet(BoxSet.rounded)
        .withTitle("Round", .top_left);

    block.render(&term.current, term.size());

    // Check rounded corners
    try testing.expectEqual('╭', term.getChar(0, 0).?);
    try testing.expectEqual('╮', term.getChar(9, 0).?);
    try testing.expectEqual('╰', term.getChar(0, 3).?);
    try testing.expectEqual('╯', term.getChar(9, 3).?);
}

// ============================================================================
// Paragraph Widget Snapshots
// ============================================================================

test "Paragraph: renders simple text" {
    var term = try MockTerminal.init(testing.allocator, 15, 3);
    defer term.deinit();

    const line = Line{ .spans = &[_]Span{Span.raw("Hello, world!")} };
    const lines = [_]Line{line};

    const para = Paragraph.fromLines(&lines);
    para.render(&term.current, term.size());

    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    try testing.expect(std.mem.indexOf(u8, snapshot, "Hello, world!") != null);
}

test "Paragraph: renders multiple lines" {
    var term = try MockTerminal.init(testing.allocator, 10, 3);
    defer term.deinit();

    const line1 = Line{ .spans = &[_]Span{Span.raw("Line 1")} };
    const line2 = Line{ .spans = &[_]Span{Span.raw("Line 2")} };
    const lines = [_]Line{ line1, line2 };

    const para = Paragraph.fromLines(&lines);
    para.render(&term.current, term.size());

    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    try testing.expect(std.mem.indexOf(u8, snapshot, "Line 1") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Line 2") != null);
}

test "Paragraph: with block border" {
    var term = try MockTerminal.init(testing.allocator, 14, 4);
    defer term.deinit();

    const block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Text", .top_left);

    const line = Line{ .spans = &[_]Span{Span.raw("Content")} };
    const lines = [_]Line{line};

    const para = Paragraph.fromLines(&lines)
        .withBlock(block);

    para.render(&term.current, term.size());

    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    // Both border and content should appear
    try testing.expectEqual('┌', term.getChar(0, 0).?);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Text") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Content") != null);
}

// ============================================================================
// List Widget Snapshots
// ============================================================================

test "List: renders basic items" {
    var term = try MockTerminal.init(testing.allocator, 12, 5);
    defer term.deinit();

    const items = [_][]const u8{ "Apple", "Banana", "Cherry" };
    const list = List.init(&items);

    list.render(&term.current, term.size());

    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    try testing.expect(std.mem.indexOf(u8, snapshot, "Apple") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Banana") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Cherry") != null);
}

test "List: selected item gets highlight symbol" {
    var term = try MockTerminal.init(testing.allocator, 10, 3);
    defer term.deinit();

    const items = [_][]const u8{ "One", "Two", "Three" };
    const list = List.init(&items)
        .withSelected(1) // Select "Two"
        .withHighlightSymbol("> ");

    list.render(&term.current, term.size());

    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    // Highlight symbol should appear before selected item
    try testing.expect(std.mem.indexOf(u8, snapshot, "> Two") != null);
}

// ============================================================================
// Table Widget Snapshots
// ============================================================================

test "Table: renders headers and rows" {
    var term = try MockTerminal.init(testing.allocator, 15, 4);
    defer term.deinit();

    const columns = [_]Column{
        .{ .title = "Name", .width = .{ .fixed = 7 } },
        .{ .title = "Age", .width = .{ .fixed = 5 } },
    };

    const row1 = [_][]const u8{ "Alice", "30" };
    const row2 = [_][]const u8{ "Bob", "25" };
    const rows = [_][]const []const u8{ &row1, &row2 };

    const table = Table.init(&columns, &rows);
    table.render(&term.current, term.size());

    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    try testing.expect(std.mem.indexOf(u8, snapshot, "Name") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Age") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Alice") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Bob") != null);
}

test "Table: with block border" {
    var term = try MockTerminal.init(testing.allocator, 16, 5);
    defer term.deinit();

    const block = (Block{})
        .withBorders(Borders.all);

    const columns = [_]Column{
        .{ .title = "ID", .width = .{ .fixed = 4 } },
        .{ .title = "Name", .width = .{ .fixed = 8 } },
    };

    const row1 = [_][]const u8{ "1", "Test" };
    const rows = [_][]const []const u8{&row1};

    const table = Table.init(&columns, &rows)
        .withBlock(block);

    table.render(&term.current, term.size());

    // Check border exists
    try testing.expectEqual('┌', term.getChar(0, 0).?);

    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    try testing.expect(std.mem.indexOf(u8, snapshot, "ID") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Test") != null);
}

// ============================================================================
// Gauge Widget Snapshots
// ============================================================================

test "Gauge: renders label at different progress levels" {
    var term = try MockTerminal.init(testing.allocator, 20, 3);
    defer term.deinit();

    const gauge = (Gauge{})
        .withPercent(50)
        .withLabel("50%");

    gauge.render(&term.current, term.size());

    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    // Should have label
    try testing.expect(std.mem.indexOf(u8, snapshot, "50%") != null);
}

test "Gauge: 100% progress renders filled bar" {
    var term = try MockTerminal.init(testing.allocator, 15, 2);
    defer term.deinit();

    const gauge = (Gauge{})
        .withPercent(100)
        .withLabel("Done");

    gauge.render(&term.current, term.size());

    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    try testing.expect(std.mem.indexOf(u8, snapshot, "Done") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "█") != null);
}

// ============================================================================
// Sparkline Widget Snapshots
// ============================================================================

test "Sparkline: renders data visualization" {
    var term = try MockTerminal.init(testing.allocator, 10, 3);
    defer term.deinit();

    const data = [_]u64{ 1, 5, 3, 7, 4 };
    const sparkline = Sparkline.init(&data);

    sparkline.render(&term.current, term.size());

    // Should render something
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    try testing.expect(snapshot.len > 0);
}

test "Sparkline: with block shows borders" {
    var term = try MockTerminal.init(testing.allocator, 12, 4);
    defer term.deinit();

    const data = [_]u64{ 2, 4, 3, 5 };
    const block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Graph", .top_left);

    const sparkline = Sparkline.init(&data)
        .withBlock(block);

    sparkline.render(&term.current, term.size());

    // Verify border exists
    try testing.expectEqual('┌', term.getChar(0, 0).?);
    try testing.expectEqual('┐', term.getChar(11, 0).?);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "Integration: multiple widgets in vertical layout" {
    var term = try MockTerminal.init(testing.allocator, 30, 10);
    defer term.deinit();

    // Top paragraph with border
    const top_block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Header", .top_left);

    const line = Line{ .spans = &[_]Span{Span.raw("Welcome")} };
    const lines = [_]Line{line};

    const para = Paragraph.fromLines(&lines)
        .withBlock(top_block);

    para.render(&term.current, Rect.new(0, 0, 30, 4));

    // Bottom list with border
    const bottom_block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Menu", .top_left);

    const items = [_][]const u8{ "Option 1", "Option 2" };
    const list = List.init(&items)
        .withBlock(bottom_block);

    list.render(&term.current, Rect.new(0, 4, 30, 6));

    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    // Both widgets should be visible
    try testing.expect(std.mem.indexOf(u8, snapshot, "Header") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Welcome") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Menu") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Option 1") != null);
}

test "Integration: side-by-side blocks" {
    var term = try MockTerminal.init(testing.allocator, 20, 4);
    defer term.deinit();

    // Left block
    const left_block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Left", .top_left);
    left_block.render(&term.current, Rect.new(0, 0, 10, 4));

    // Right block
    const right_block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Right", .top_left);
    right_block.render(&term.current, Rect.new(10, 0, 10, 4));

    // Both should render without overlapping
    try testing.expectEqual('┌', term.getChar(0, 0).?);
    try testing.expectEqual('┌', term.getChar(10, 0).?);
    try testing.expectEqual('┘', term.getChar(9, 3).?);
    try testing.expectEqual('┘', term.getChar(19, 3).?);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "Edge case: zero-size area does not crash" {
    var term = try MockTerminal.init(testing.allocator, 10, 5);
    defer term.deinit();

    const block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Test", .top_left);

    // Should not crash
    block.render(&term.current, Rect.new(0, 0, 0, 0));

    // Terminal should remain empty
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    for (snapshot) |char| {
        if (char != ' ' and char != '\n') {
            return error.TestFailed; // Found non-space
        }
    }
}

test "Edge case: single-char area renders content" {
    var term = try MockTerminal.init(testing.allocator, 5, 3);
    defer term.deinit();

    const line = Line{ .spans = &[_]Span{Span.raw("X")} };
    const lines = [_]Line{line};

    const para = Paragraph.fromLines(&lines);
    para.render(&term.current, Rect.new(2, 1, 1, 1));

    // Should render single char at position
    try testing.expectEqual('X', term.getChar(2, 1).?);
}

// ============================================================================
// Style Testing
// ============================================================================

test "Style: Block with colored border" {
    var term = try MockTerminal.init(testing.allocator, 10, 4);
    defer term.deinit();

    const block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Color", .top_left)
        .withBorderStyle(Style{ .fg = .blue });

    block.render(&term.current, term.size());

    // Check border is rendered
    try testing.expectEqual('┌', term.getChar(0, 0).?);

    // Check style has blue foreground
    const style = term.getStyle(0, 0).?;
    try testing.expectEqual(Color.blue, style.fg);
}

test "Style: Paragraph with styled spans" {
    var term = try MockTerminal.init(testing.allocator, 20, 2);
    defer term.deinit();

    const spans = [_]Span{
        Span.styled("Bold ", Style{ .bold = true }),
        Span.styled("Italic", Style{ .italic = true }),
    };

    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};

    const para = Paragraph.fromLines(&lines);
    para.render(&term.current, term.size());

    // Check bold style at position 0
    const bold_style = term.getStyle(0, 0).?;
    try testing.expect(bold_style.bold);

    // Check italic style at position 5
    const italic_style = term.getStyle(5, 0).?;
    try testing.expect(italic_style.italic);
}
