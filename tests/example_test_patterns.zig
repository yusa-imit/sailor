//! Example Test Patterns for Sailor TUI Applications
//!
//! This file demonstrates comprehensive integration testing patterns for
//! applications built with sailor. It serves as a reference for developers
//! building their own TUI applications and needing to write tests.
//!
//! Patterns demonstrated:
//! - MockTerminal-based widget testing
//! - Multi-widget layout composition
//! - Error handling and edge cases
//! - Styled output verification
//! - State management patterns

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

// Widget imports
const Block = sailor.tui.widgets.Block;
const Borders = sailor.tui.widgets.Borders;
const Paragraph = sailor.tui.widgets.Paragraph;
const List = sailor.tui.widgets.List;
const Input = sailor.tui.widgets.Input;
const Table = sailor.tui.widgets.Table;
const Column = sailor.tui.widgets.Column;
const Gauge = sailor.tui.widgets.Gauge;

// ============================================================================
// Pattern 1: Testing Widget Rendering
// ============================================================================

// Example: Testing basic widget rendering with MockTerminal
test "Pattern: Basic widget rendering verification" {
    var term = try MockTerminal.init(testing.allocator, 20, 5);
    defer term.deinit();

    // Create and render a simple block
    const block = Block{}
        .withBorders(Borders.all)
        .withTitle("Test", .top_left);

    block.render(&term.current, term.size());

    // Verify structure
    try testing.expectEqual('┌', term.getChar(0, 0).?);
    try testing.expectEqual('┐', term.getChar(19, 0).?);
    try testing.expectEqual('└', term.getChar(0, 4).?);
    try testing.expectEqual('┘', term.getChar(19, 4).?);

    // Verify content
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Test") != null);
}

// ============================================================================
// Pattern 2: Testing Multi-Widget Layouts
// ============================================================================

// Example: Testing dashboard layout with multiple widgets
test "Pattern: Multi-widget dashboard layout" {
    var term = try MockTerminal.init(testing.allocator, 40, 20);
    defer term.deinit();

    // Define layout areas (simulating Layout.split)
    const header_area = Rect.new(0, 0, 40, 3);
    const footer_area = Rect.new(0, 17, 40, 3);

    // Header: Title block
    const header_block = Block{}
        .withBorders(Borders.all)
        .withTitle("Dashboard", .top_left);
    header_block.render(&term.current, header_area);

    // Content: Split into left panel (list) and right panel (gauge)
    const left_area = Rect.new(0, 3, 20, 14);
    const right_area = Rect.new(20, 3, 20, 14);

    // Left panel: Task list
    const tasks = [_][]const u8{ "Build", "Test", "Deploy" };
    const task_list = List.init(&tasks)
        .withBlock(Block{}.withBorders(Borders.all).withTitle("Tasks", .top_left))
        .withSelected(1);
    task_list.render(&term.current, left_area);

    // Right panel: Progress gauge
    const progress_block = Block{}
        .withBorders(Borders.all)
        .withTitle("Progress", .top_left);

    const gauge = Gauge{}
        .withPercent(75)
        .withLabel("75%")
        .withBlock(progress_block);
    gauge.render(&term.current, right_area);

    // Footer: Status bar
    const footer_block = Block{}
        .withBorders(Borders.all);
    footer_block.render(&term.current, footer_area);

    // Verify all sections rendered without overlap
    try testing.expectEqual('┌', term.getChar(0, 0).?); // Header top-left
    try testing.expectEqual('┌', term.getChar(0, 3).?); // Left panel top-left
    try testing.expectEqual('┌', term.getChar(20, 3).?); // Right panel top-left
    try testing.expectEqual('┌', term.getChar(0, 17).?); // Footer top-left

    // Verify content appears in correct panels
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    try testing.expect(std.mem.indexOf(u8, snapshot, "Dashboard") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Tasks") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Progress") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Build") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "75%") != null);
}

// ============================================================================
// Pattern 3: Testing Widget State Changes
// ============================================================================

// Example: Testing list selection changes
test "Pattern: Widget state management" {
    var term = try MockTerminal.init(testing.allocator, 15, 5);
    defer term.deinit();

    const items = [_][]const u8{ "Item 1", "Item 2", "Item 3", "Item 4" };

    // Initial state: first item selected
    var list = List.init(&items)
        .withSelected(0)
        .withHighlightSymbol("> ");

    try testing.expectEqual(@as(usize, 0), list.selected.?);

    // Change selection to second item
    list = list.withSelected(1);
    try testing.expectEqual(@as(usize, 1), list.selected.?);

    // Render and verify highlight symbol appears at correct position
    list.render(&term.current, term.size());
    try testing.expectEqual('>', term.getChar(0, 1).?);

    // Change selection to last item
    list = list.withSelected(3);
    term.current.clear();
    list.render(&term.current, term.size());
    try testing.expectEqual('>', term.getChar(0, 3).?);
}

// ============================================================================
// Pattern 4: Testing Error Handling
// ============================================================================

// Example: Testing widget behavior with invalid data
test "Pattern: Widget error handling with empty data" {
    var term = try MockTerminal.init(testing.allocator, 20, 5);
    defer term.deinit();

    // Empty list should not crash
    const empty_items: []const []const u8 = &[_][]const u8{};
    const empty_list = List.init(empty_items);
    empty_list.render(&term.current, term.size());

    // Terminal should be empty (no items to render)
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    // All whitespace is ok
    for (snapshot) |char| {
        try testing.expect(char == ' ' or char == '\n');
    }
}

// Example: Testing widget behavior with zero-size area
test "Pattern: Widget rendering in zero-size area" {
    var term = try MockTerminal.init(testing.allocator, 20, 10);
    defer term.deinit();

    const block = Block{}
        .withBorders(Borders.all)
        .withTitle("Test", .top_left);

    // Should not crash with zero width
    block.render(&term.current, Rect.new(0, 0, 0, 5));

    // Should not crash with zero height
    block.render(&term.current, Rect.new(0, 0, 10, 0));

    // Should not crash with both zero
    block.render(&term.current, Rect.new(0, 0, 0, 0));

    // Terminal should remain empty after rendering to zero-size areas
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    for (snapshot) |char| {
        try testing.expect(char == ' ' or char == '\n');
    }
}

// ============================================================================
// Pattern 5: Testing Table Widget with Structured Data
// ============================================================================

// Example: Testing table with various data types
test "Pattern: Table widget with structured data" {
    var term = try MockTerminal.init(testing.allocator, 30, 6);
    defer term.deinit();

    const columns = [_]Column{
        .{ .title = "ID", .width = .{ .fixed = 4 } },
        .{ .title = "Name", .width = .{ .fixed = 10 } },
        .{ .title = "Status", .width = .{ .fixed = 8 } },
    };

    const row1 = [_][]const u8{ "1", "Alice", "Active" };
    const row2 = [_][]const u8{ "2", "Bob", "Pending" };
    const row3 = [_][]const u8{ "3", "Charlie", "Inactive" };
    const rows = [_][]const []const u8{ &row1, &row2, &row3 };

    const table = Table.init(&columns, &rows);
    table.render(&term.current, term.size());

    // Verify headers render
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);

    try testing.expect(std.mem.indexOf(u8, snapshot, "ID") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Name") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Status") != null);

    // Verify data rows render
    try testing.expect(std.mem.indexOf(u8, snapshot, "Alice") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Bob") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Charlie") != null);
}

// ============================================================================
// Pattern 6: Testing Progressive Rendering
// ============================================================================

// Example: Testing incremental updates (like live progress)
test "Pattern: Progressive gauge updates" {
    var term = try MockTerminal.init(testing.allocator, 20, 2);
    defer term.deinit();

    // Simulate progress from 0% to 100% in steps
    var percent: u8 = 0;
    while (percent <= 100) : (percent += 25) {
        term.current.clear();

        var buf: [10]u8 = undefined;
        const label = try std.fmt.bufPrint(&buf, "{d}%", .{percent});

        const gauge = Gauge{}
            .withPercent(percent)
            .withLabel(label);

        gauge.render(&term.current, term.size());

        // Verify label appears
        const snapshot = try term.getSnapshot(testing.allocator);
        defer testing.allocator.free(snapshot);

        try testing.expect(std.mem.indexOf(u8, snapshot, label) != null);

        // At 0%, no fill blocks
        if (percent == 0) {
            try testing.expect(std.mem.indexOf(u8, snapshot, "█") == null);
        }
        // At 100%, should have fill blocks
        if (percent == 100) {
            try testing.expect(std.mem.indexOf(u8, snapshot, "█") != null);
        }
    }
}

// ============================================================================
// Pattern 7: Testing Styled Output
// ============================================================================

// Example: Verifying style attributes are applied
test "Pattern: Style verification" {
    var term = try MockTerminal.init(testing.allocator, 15, 2);
    defer term.deinit();

    // Create styled text
    const spans = [_]Span{
        Span.styled("Error: ", Style{ .fg = .red, .bold = true }),
        Span.styled("Failed", Style{ .fg = .red }),
    };

    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};

    const para = Paragraph.fromLines(&lines);
    para.render(&term.current, term.size());

    // Verify styles applied at correct positions
    const style_at_0 = term.getStyle(0, 0).?;
    try testing.expectEqual(Color.red, style_at_0.fg);
    try testing.expect(style_at_0.bold);

    const style_at_7 = term.getStyle(7, 0).?;
    try testing.expectEqual(Color.red, style_at_7.fg);
    try testing.expect(!style_at_7.bold); // Second span not bold
}

// ============================================================================
// Pattern 8: Testing Layout Composition
// ============================================================================

// Example: Testing side-by-side widget layout
test "Pattern: Horizontal layout composition" {
    var term = try MockTerminal.init(testing.allocator, 30, 5);
    defer term.deinit();

    // Left widget
    const left_block = Block{}
        .withBorders(Borders.all)
        .withTitle("Left", .top_left);
    left_block.render(&term.current, Rect.new(0, 0, 15, 5));

    // Right widget
    const right_block = Block{}
        .withBorders(Borders.all)
        .withTitle("Right", .top_left);
    right_block.render(&term.current, Rect.new(15, 0, 15, 5));

    // Verify both rendered without overlap
    try testing.expectEqual('┌', term.getChar(0, 0).?); // Left top-left
    try testing.expectEqual('┘', term.getChar(14, 4).?); // Left bottom-right
    try testing.expectEqual('┌', term.getChar(15, 0).?); // Right top-left
    try testing.expectEqual('┘', term.getChar(29, 4).?); // Right bottom-right

    // Verify titles
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Left") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Right") != null);
}

// Example: Testing vertical stack layout
test "Pattern: Vertical layout composition" {
    var term = try MockTerminal.init(testing.allocator, 20, 8);
    defer term.deinit();

    // Top widget
    const top = Block{}
        .withBorders(Borders.all)
        .withTitle("Top", .top_left);
    top.render(&term.current, Rect.new(0, 0, 20, 4));

    // Bottom widget
    const bottom = Block{}
        .withBorders(Borders.all)
        .withTitle("Bottom", .top_left);
    bottom.render(&term.current, Rect.new(0, 4, 20, 4));

    // Verify separation
    try testing.expectEqual('└', term.getChar(0, 3).?); // Top bottom-left
    try testing.expectEqual('┌', term.getChar(0, 4).?); // Bottom top-left

    // Verify titles
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Top") != null);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Bottom") != null);
}
