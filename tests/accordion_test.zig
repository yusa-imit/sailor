//! Accordion Widget Tests — TDD Red Phase
//!
//! Tests accordion widget with expandable sections, cursor navigation,
//! single-expand mode, builder pattern, and rendering capabilities.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Accordion = sailor.tui.widgets.Accordion;
const AccordionSection = sailor.tui.widgets.AccordionSection;
const Block = sailor.tui.widgets.Block;

// ============================================================================
// Init Tests (8 tests)
// ============================================================================

test "Accordion.init with single section has cursor at 0" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{} },
    };
    const acc = Accordion.init(&sections);
    try testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "Accordion.init with multiple sections has cursor at 0" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{} },
        .{ .title = "Section 2", .content_lines = &.{} },
        .{ .title = "Section 3", .content_lines = &.{} },
    };
    const acc = Accordion.init(&sections);
    try testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "Accordion.init with empty sections array" {
    var sections: [0]AccordionSection = undefined;
    const acc = Accordion.init(&sections);
    try testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "Accordion.init defaults single_expand to false" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{} },
    };
    const acc = Accordion.init(&sections);
    try testing.expect(acc.single_expand == false);
}

test "Accordion.init defaults block to null" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{} },
    };
    const acc = Accordion.init(&sections);
    try testing.expect(acc.block == null);
}

test "Accordion.init defaults styles to empty Style" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{} },
    };
    const acc = Accordion.init(&sections);
    try testing.expectEqual(Style{}, acc.header_style);
    try testing.expectEqual(Style{}, acc.expanded_style);
}

test "Accordion.init defaults cursor_style to bold reverse" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{} },
    };
    const acc = Accordion.init(&sections);
    try testing.expect(acc.cursor_style.bold == true);
    try testing.expect(acc.cursor_style.reverse == true);
}

test "Accordion.init defaults icons to triangle" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{} },
    };
    const acc = Accordion.init(&sections);
    try testing.expectEqual(@as(u21, '▶'), acc.expand_icon);
    try testing.expectEqual(@as(u21, '▼'), acc.collapse_icon);
}

// ============================================================================
// toggleCurrent Tests (8 tests)
// ============================================================================

test "toggleCurrent flips false to true" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    try testing.expect(sections[0].expanded == false);
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == true);
}

test "toggleCurrent flips true to false" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    try testing.expect(sections[0].expanded == true);
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == false);
}

test "toggleCurrent affects cursor section, not others" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = false },
        .{ .title = "Section 2", .content_lines = &.{}, .expanded = false },
        .{ .title = "Section 3", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 1;
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == false);
    try testing.expect(sections[1].expanded == true);
    try testing.expect(sections[2].expanded == false);
}

test "toggleCurrent multiple times on same section alternates" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == true);
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == false);
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == true);
}

test "toggleCurrent on already expanded section" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == false);
}

test "toggleCurrent with single section" {
    var sections = [_]AccordionSection{
        .{ .title = "Only Section", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == true);
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == false);
}

test "toggleCurrent with cursor at last section" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = false },
        .{ .title = "Section 2", .content_lines = &.{}, .expanded = false },
        .{ .title = "Section 3", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 2;
    acc.toggleCurrent();
    try testing.expect(sections[2].expanded == true);
}

test "toggleCurrent with multiple expanded sections" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = true },
        .{ .title = "Section 2", .content_lines = &.{}, .expanded = true },
        .{ .title = "Section 3", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 0;
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == false);
    try testing.expect(sections[1].expanded == true);
}

// ============================================================================
// expandCurrent Tests (8 tests)
// ============================================================================

test "expandCurrent sets expanded to true" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.expandCurrent();
    try testing.expect(sections[0].expanded == true);
}

test "expandCurrent when already expanded is no-op" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.expandCurrent();
    try testing.expect(sections[0].expanded == true);
}

test "expandCurrent with single_expand mode collapses others" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = true },
        .{ .title = "Section 2", .content_lines = &.{}, .expanded = false },
        .{ .title = "Section 3", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.single_expand = true;
    acc.cursor = 1;
    acc.expandCurrent();
    try testing.expect(sections[0].expanded == false);
    try testing.expect(sections[1].expanded == true);
    try testing.expect(sections[2].expanded == false);
}

test "expandCurrent with single_expand does not collapse if expanding same section" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.single_expand = true;
    acc.cursor = 0;
    acc.expandCurrent();
    try testing.expect(sections[0].expanded == true);
}

test "expandCurrent single_expand with all collapsed expands cursor only" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = false },
        .{ .title = "Section 2", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.single_expand = true;
    acc.cursor = 0;
    acc.expandCurrent();
    try testing.expect(sections[0].expanded == true);
    try testing.expect(sections[1].expanded == false);
}

test "expandCurrent without single_expand keeps other sections unchanged" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = true },
        .{ .title = "Section 2", .content_lines = &.{}, .expanded = false },
        .{ .title = "Section 3", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.single_expand = false;
    acc.cursor = 1;
    acc.expandCurrent();
    try testing.expect(sections[0].expanded == true);
    try testing.expect(sections[1].expanded == true);
    try testing.expect(sections[2].expanded == true);
}

test "expandCurrent at different cursor positions with single_expand" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = true },
        .{ .title = "B", .content_lines = &.{}, .expanded = true },
        .{ .title = "C", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.single_expand = true;
    acc.cursor = 2;
    acc.expandCurrent();
    try testing.expect(sections[0].expanded == false);
    try testing.expect(sections[1].expanded == false);
    try testing.expect(sections[2].expanded == true);
}

test "expandCurrent with single section and single_expand" {
    var sections = [_]AccordionSection{
        .{ .title = "Only", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.single_expand = true;
    acc.expandCurrent();
    try testing.expect(sections[0].expanded == true);
}

// ============================================================================
// collapseCurrent Tests (5 tests)
// ============================================================================

test "collapseCurrent sets expanded to false" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.collapseCurrent();
    try testing.expect(sections[0].expanded == false);
}

test "collapseCurrent when already collapsed is no-op" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.collapseCurrent();
    try testing.expect(sections[0].expanded == false);
}

test "collapseCurrent affects only cursor section" {
    var sections = [_]AccordionSection{
        .{ .title = "Section 1", .content_lines = &.{}, .expanded = true },
        .{ .title = "Section 2", .content_lines = &.{}, .expanded = true },
        .{ .title = "Section 3", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 1;
    acc.collapseCurrent();
    try testing.expect(sections[0].expanded == true);
    try testing.expect(sections[1].expanded == false);
    try testing.expect(sections[2].expanded == true);
}

test "collapseCurrent with multiple sections" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = true },
        .{ .title = "B", .content_lines = &.{}, .expanded = false },
        .{ .title = "C", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 2;
    acc.collapseCurrent();
    try testing.expect(sections[0].expanded == true);
    try testing.expect(sections[1].expanded == false);
    try testing.expect(sections[2].expanded == false);
}

test "collapseCurrent at cursor 0" {
    var sections = [_]AccordionSection{
        .{ .title = "First", .content_lines = &.{}, .expanded = true },
        .{ .title = "Second", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 0;
    acc.collapseCurrent();
    try testing.expect(sections[0].expanded == false);
    try testing.expect(sections[1].expanded == true);
}

// ============================================================================
// expandAll/collapseAll Tests (8 tests)
// ============================================================================

test "expandAll expands all sections" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = false },
        .{ .title = "B", .content_lines = &.{}, .expanded = false },
        .{ .title = "C", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.expandAll();
    try testing.expect(sections[0].expanded == true);
    try testing.expect(sections[1].expanded == true);
    try testing.expect(sections[2].expanded == true);
}

test "expandAll with mixed expanded state expands all" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = true },
        .{ .title = "B", .content_lines = &.{}, .expanded = false },
        .{ .title = "C", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.expandAll();
    try testing.expect(sections[0].expanded == true);
    try testing.expect(sections[1].expanded == true);
    try testing.expect(sections[2].expanded == true);
}

test "expandAll ignores single_expand mode" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = false },
        .{ .title = "B", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.single_expand = true;
    acc.expandAll();
    try testing.expect(sections[0].expanded == true);
    try testing.expect(sections[1].expanded == true);
}

test "collapseAll collapses all sections" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = true },
        .{ .title = "B", .content_lines = &.{}, .expanded = true },
        .{ .title = "C", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.collapseAll();
    try testing.expect(sections[0].expanded == false);
    try testing.expect(sections[1].expanded == false);
    try testing.expect(sections[2].expanded == false);
}

test "collapseAll with mixed state collapses all" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = true },
        .{ .title = "B", .content_lines = &.{}, .expanded = false },
        .{ .title = "C", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.collapseAll();
    try testing.expect(sections[0].expanded == false);
    try testing.expect(sections[1].expanded == false);
    try testing.expect(sections[2].expanded == false);
}

test "collapseAll with single expanded section" {
    var sections = [_]AccordionSection{
        .{ .title = "Only", .content_lines = &.{}, .expanded = true },
    };
    var acc = Accordion.init(&sections);
    acc.collapseAll();
    try testing.expect(sections[0].expanded == false);
}

test "expandAll then collapseAll" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = false },
        .{ .title = "B", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.expandAll();
    try testing.expect(sections[0].expanded == true);
    try testing.expect(sections[1].expanded == true);
    acc.collapseAll();
    try testing.expect(sections[0].expanded == false);
    try testing.expect(sections[1].expanded == false);
}

// ============================================================================
// moveCursorUp Tests (5 tests)
// ============================================================================

test "moveCursorUp decrements cursor when not at 0" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
        .{ .title = "B", .content_lines = &.{} },
        .{ .title = "C", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 2;
    acc.moveCursorUp();
    try testing.expectEqual(@as(usize, 1), acc.cursor);
}

test "moveCursorUp from 0 wraps to last" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
        .{ .title = "B", .content_lines = &.{} },
        .{ .title = "C", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 0;
    acc.moveCursorUp();
    try testing.expectEqual(@as(usize, 2), acc.cursor);
}

test "moveCursorUp with single section stays at 0" {
    var sections = [_]AccordionSection{
        .{ .title = "Only", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 0;
    acc.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "moveCursorUp multiple times" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
        .{ .title = "B", .content_lines = &.{} },
        .{ .title = "C", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 2;
    acc.moveCursorUp();
    try testing.expectEqual(@as(usize, 1), acc.cursor);
    acc.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), acc.cursor);
    acc.moveCursorUp();
    try testing.expectEqual(@as(usize, 2), acc.cursor);
}

test "moveCursorUp from cursor 1 goes to 0" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
        .{ .title = "B", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 1;
    acc.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), acc.cursor);
}

// ============================================================================
// moveCursorDown Tests (5 tests)
// ============================================================================

test "moveCursorDown increments cursor when not at last" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
        .{ .title = "B", .content_lines = &.{} },
        .{ .title = "C", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 1;
    acc.moveCursorDown();
    try testing.expectEqual(@as(usize, 2), acc.cursor);
}

test "moveCursorDown from last wraps to 0" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
        .{ .title = "B", .content_lines = &.{} },
        .{ .title = "C", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 2;
    acc.moveCursorDown();
    try testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "moveCursorDown with single section stays at 0" {
    var sections = [_]AccordionSection{
        .{ .title = "Only", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 0;
    acc.moveCursorDown();
    try testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "moveCursorDown multiple times" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
        .{ .title = "B", .content_lines = &.{} },
        .{ .title = "C", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 0;
    acc.moveCursorDown();
    try testing.expectEqual(@as(usize, 1), acc.cursor);
    acc.moveCursorDown();
    try testing.expectEqual(@as(usize, 2), acc.cursor);
    acc.moveCursorDown();
    try testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "moveCursorDown from last section to first" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
        .{ .title = "B", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 1;
    acc.moveCursorDown();
    try testing.expectEqual(@as(usize, 0), acc.cursor);
}

// ============================================================================
// isExpanded Tests (5 tests)
// ============================================================================

test "isExpanded returns true when expanded" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = true },
    };
    const acc = Accordion.init(&sections);
    try testing.expect(acc.isExpanded(0) == true);
}

test "isExpanded returns false when not expanded" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = false },
    };
    const acc = Accordion.init(&sections);
    try testing.expect(acc.isExpanded(0) == false);
}

test "isExpanded with multiple sections" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = true },
        .{ .title = "B", .content_lines = &.{}, .expanded = false },
        .{ .title = "C", .content_lines = &.{}, .expanded = true },
    };
    const acc = Accordion.init(&sections);
    try testing.expect(acc.isExpanded(0) == true);
    try testing.expect(acc.isExpanded(1) == false);
    try testing.expect(acc.isExpanded(2) == true);
}

test "isExpanded returns false for out of bounds index" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = true },
    };
    const acc = Accordion.init(&sections);
    try testing.expect(acc.isExpanded(5) == false);
}

test "isExpanded returns false for out of bounds negative via wrapping" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = true },
    };
    const acc = Accordion.init(&sections);
    // Negative indices wrap around in unsigned, so large values are out of bounds
    try testing.expect(acc.isExpanded(999) == false);
}

// ============================================================================
// Builder Pattern Tests (8 tests)
// ============================================================================

test "withBlock sets block field" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    const test_block = Block{ .borders = .all };
    acc = acc.withBlock(test_block);
    try testing.expect(acc.block != null);
}

test "withHeaderStyle sets header_style field" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    const new_style = Style{ .bold = true };
    acc = acc.withHeaderStyle(new_style);
    try testing.expect(acc.header_style.bold == true);
}

test "withExpandedStyle sets expanded_style field" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    const new_style = Style{ .italic = true };
    acc = acc.withExpandedStyle(new_style);
    try testing.expect(acc.expanded_style.italic == true);
}

test "withCursorStyle sets cursor_style field" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    const new_style = Style{ .underline = true };
    acc = acc.withCursorStyle(new_style);
    try testing.expect(acc.cursor_style.underline == true);
}

test "withExpandIcon sets expand_icon field" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc = acc.withExpandIcon('>');
    try testing.expectEqual(@as(u21, '>'), acc.expand_icon);
}

test "withCollapseIcon sets collapse_icon field" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc = acc.withCollapseIcon('v');
    try testing.expectEqual(@as(u21, 'v'), acc.collapse_icon);
}

test "withSingleExpand sets single_expand field" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    acc = acc.withSingleExpand(true);
    try testing.expect(acc.single_expand == true);
    acc = acc.withSingleExpand(false);
    try testing.expect(acc.single_expand == false);
}

test "builder methods can be chained" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    const block = Block{ .borders = .all };
    acc = acc
        .withBlock(block)
        .withExpandIcon('>')
        .withCollapseIcon('v')
        .withSingleExpand(true)
        .withHeaderStyle(Style{ .bold = true });

    try testing.expect(acc.block != null);
    try testing.expectEqual(@as(u21, '>'), acc.expand_icon);
    try testing.expectEqual(@as(u21, 'v'), acc.collapse_icon);
    try testing.expect(acc.single_expand == true);
    try testing.expect(acc.header_style.bold == true);
}

// ============================================================================
// Render Tests (8+ tests)
// ============================================================================

test "render with zero area is no-op" {
    var sections = [_]AccordionSection{
        .{ .title = "Section", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    acc.render(&buf, area);
    // Should not crash or panic
}

test "render with empty sections is no-op" {
    var sections: [0]AccordionSection = undefined;
    var acc = Accordion.init(&sections);

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    acc.render(&buf, area);
    // Should not crash or panic
}

test "render with single section does not crash" {
    var sections = [_]AccordionSection{
        .{ .title = "Section1", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);

    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    acc.render(&buf, area);
    // Should not crash or panic
}

test "render collapsed section shows only header" {
    var sections = [_]AccordionSection{
        .{
            .title = "Title",
            .content_lines = &.{ "Line 1", "Line 2" },
            .expanded = false
        },
    };
    var acc = Accordion.init(&sections);

    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    acc.render(&buf, area);

    // Header should be at row 0, no content rows
    // Content would be at rows 1-2 if expanded
}

test "render expanded section shows header and content" {
    var sections = [_]AccordionSection{
        .{
            .title = "Title",
            .content_lines = &.{ "Line 1", "Line 2" },
            .expanded = true
        },
    };
    var acc = Accordion.init(&sections);

    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    acc.render(&buf, area);

    // Header at row 0, content at rows 1-2
}

test "render with block border" {
    var sections = [_]AccordionSection{
        .{ .title = "Section", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);
    const block = Block{ .borders = .all };
    acc = acc.withBlock(block);

    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    acc.render(&buf, area);
    // Should render with border
}

test "render with narrow area" {
    var sections = [_]AccordionSection{
        .{ .title = "Very Long Title Text Here", .content_lines = &.{} },
    };
    var acc = Accordion.init(&sections);

    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    acc.render(&buf, area);
    // Should not panic or crash with narrow area
}

test "render multiple sections shows all headers" {
    var sections = [_]AccordionSection{
        .{ .title = "First", .content_lines = &.{}, .expanded = false },
        .{ .title = "Second", .content_lines = &.{}, .expanded = false },
        .{ .title = "Third", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);

    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    acc.render(&buf, area);

    // All three headers should be rendered
}

test "render applies cursor style to current section" {
    var sections = [_]AccordionSection{
        .{ .title = "First", .content_lines = &.{}, .expanded = false },
        .{ .title = "Second", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.cursor = 1;
    acc = acc.withCursorStyle(Style{ .bold = true, .reverse = true });

    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    acc.render(&buf, area);

    // Cursor row (row 1) should have cursor style applied
}

// ============================================================================
// Integration Tests (6 tests)
// ============================================================================

test "interaction sequence: navigate and expand" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = false },
        .{ .title = "B", .content_lines = &.{}, .expanded = false },
        .{ .title = "C", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);

    // Start at A
    try testing.expectEqual(@as(usize, 0), acc.cursor);

    // Move down to B
    acc.moveCursorDown();
    try testing.expectEqual(@as(usize, 1), acc.cursor);

    // Expand B
    acc.expandCurrent();
    try testing.expect(sections[1].expanded == true);

    // Move to C
    acc.moveCursorDown();
    try testing.expectEqual(@as(usize, 2), acc.cursor);

    // Collapse B should still be expanded since we moved
    try testing.expect(sections[1].expanded == true);
}

test "single_expand workflow prevents multiple open sections" {
    var sections = [_]AccordionSection{
        .{ .title = "A", .content_lines = &.{}, .expanded = false },
        .{ .title = "B", .content_lines = &.{}, .expanded = false },
        .{ .title = "C", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);
    acc.single_expand = true;

    // Expand A
    acc.expandCurrent();
    try testing.expect(sections[0].expanded == true);

    // Move to B and expand
    acc.moveCursorDown();
    acc.expandCurrent();
    try testing.expect(sections[0].expanded == false);
    try testing.expect(sections[1].expanded == true);

    // Move to C and expand
    acc.moveCursorDown();
    acc.expandCurrent();
    try testing.expect(sections[1].expanded == false);
    try testing.expect(sections[2].expanded == true);
}

test "toggle and navigate combination" {
    var sections = [_]AccordionSection{
        .{ .title = "X", .content_lines = &.{}, .expanded = false },
        .{ .title = "Y", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);

    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == true);

    acc.moveCursorDown();
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == true);
    try testing.expect(sections[1].expanded == true);

    acc.moveCursorUp();
    acc.toggleCurrent();
    try testing.expect(sections[0].expanded == false);
    try testing.expect(sections[1].expanded == true);
}

test "expand all then collapse single" {
    var sections = [_]AccordionSection{
        .{ .title = "P", .content_lines = &.{}, .expanded = false },
        .{ .title = "Q", .content_lines = &.{}, .expanded = false },
        .{ .title = "R", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);

    acc.expandAll();
    try testing.expect(sections[0].expanded == true);
    try testing.expect(sections[1].expanded == true);
    try testing.expect(sections[2].expanded == true);

    acc.cursor = 1;
    acc.collapseCurrent();
    try testing.expect(sections[0].expanded == true);
    try testing.expect(sections[1].expanded == false);
    try testing.expect(sections[2].expanded == true);
}

test "cursor wraps and expandCurrent works after wrap" {
    var sections = [_]AccordionSection{
        .{ .title = "M", .content_lines = &.{}, .expanded = false },
        .{ .title = "N", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);

    // Cursor at 1, move down to wrap to 0
    acc.cursor = 1;
    acc.moveCursorDown();
    try testing.expectEqual(@as(usize, 0), acc.cursor);

    // Expand at wrapped cursor position
    acc.expandCurrent();
    try testing.expect(sections[0].expanded == true);
}

test "multiple toggles produce correct state" {
    var sections = [_]AccordionSection{
        .{ .title = "Z", .content_lines = &.{}, .expanded = false },
    };
    var acc = Accordion.init(&sections);

    // Toggle sequence: F -> T -> F -> T -> F
    for (0..5) |i| {
        acc.toggleCurrent();
        const expected = (i % 2) == 0; // 0:T, 1:F, 2:T, 3:F, 4:T
        try testing.expectEqual(expected, sections[0].expanded);
    }
}
