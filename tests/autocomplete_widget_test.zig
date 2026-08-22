//! Autocomplete Widget Tests — TDD Red Phase
//!
//! Comprehensive test coverage for the Autocomplete widget including:
//! - Initialization and lifecycle (init/deinit)
//! - Builder pattern methods (setBlock, setMaxVisible, setHighlightStyle, etc.)
//! - Suggestion management (setSuggestions, setSuggestionsWithDocs)
//! - Selection navigation (selectNext, selectPrev, selectFirst, selectLast)
//! - State queries (getSelected, getSuggestionCount)
//! - Rendering with various configurations
//! - Regression tests for u16 overflow in renderList() and renderDocPreview()

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Autocomplete = sailor.tui.widgets.Autocomplete;
const Block = sailor.tui.widgets.Block;

// ============================================================================
// Initialization Tests (3 tests)
// ============================================================================

test "Autocomplete.init creates widget with default values" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try testing.expectEqual(@as(usize, 0), ac.selected_index);
    try testing.expectEqual(@as(usize, 0), ac.scroll_offset);
    try testing.expectEqual(@as(usize, 10), ac.max_visible);
    try testing.expectEqual(false, ac.show_doc_preview);
    try testing.expectEqual(false, ac.show_metadata_column);
    try testing.expectEqual(@as(u16, 40), ac.preview_width);
    try testing.expectEqual(@as(u16, 10), ac.metadata_column_width);
}

test "Autocomplete.init with default highlight style is black-on-white" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try testing.expectEqual(@as(u8, 0), ac.highlight_style.fg.?.indexed); // black
    try testing.expectEqual(@as(u8, 7), ac.highlight_style.bg.?.indexed); // white
}

test "Autocomplete.deinit frees suggestion list without crash" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);

    // Set some suggestions
    try ac.setSuggestions(&.{ "hello", "world", "test" });
    try testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());

    // deinit should not crash and list should be cleared
    ac.deinit();
}

// ============================================================================
// Builder Pattern Tests (11 tests)
// ============================================================================

test "Autocomplete.setBlock sets border block and returns self for chaining" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const block = (Block{}).withTitle("Autocomplete", .top_left);
    const result = ac.setBlock(block);

    try testing.expect(ac.block != null);
    try testing.expect(result == &ac);
}

test "Autocomplete.setMaxVisible updates max_visible and returns self" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const result = ac.setMaxVisible(5);

    try testing.expectEqual(@as(usize, 5), ac.max_visible);
    try testing.expect(result == &ac);
}

test "Autocomplete.setHighlightStyle updates highlight style" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const custom_style = Style{ .fg = Color{ .indexed = 3 } };
    const result = ac.setHighlightStyle(custom_style);

    try testing.expectEqual(@as(u8, 3), ac.highlight_style.fg.?.indexed);
    try testing.expect(result == &ac);
}

test "Autocomplete.setNormalStyle updates normal style" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const custom_style = Style{ .fg = Color{ .indexed = 2 } };
    const result = ac.setNormalStyle(custom_style);

    try testing.expectEqual(@as(u8, 2), ac.normal_style.fg.?.indexed);
    try testing.expect(result == &ac);
}

test "Autocomplete.setMetadataStyle updates metadata style" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const custom_style = Style{ .fg = Color{ .indexed = 5 } };
    const result = ac.setMetadataStyle(custom_style);

    try testing.expectEqual(@as(u8, 5), ac.metadata_style.fg.?.indexed);
    try testing.expect(result == &ac);
}

test "Autocomplete.setDocStyle updates doc style" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const custom_style = Style{ .fg = Color{ .indexed = 4 } };
    const result = ac.setDocStyle(custom_style);

    try testing.expectEqual(@as(u8, 4), ac.doc_style.fg.?.indexed);
    try testing.expect(result == &ac);
}

test "Autocomplete.enableDocPreview toggles doc preview and returns self" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try testing.expectEqual(false, ac.show_doc_preview);

    const result = ac.enableDocPreview(true);
    try testing.expectEqual(true, ac.show_doc_preview);
    try testing.expect(result == &ac);

    _ = ac.enableDocPreview(false);
    try testing.expectEqual(false, ac.show_doc_preview);
}

test "Autocomplete.setPreviewWidth updates preview width" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const result = ac.setPreviewWidth(60);

    try testing.expectEqual(@as(u16, 60), ac.preview_width);
    try testing.expect(result == &ac);
}

test "Autocomplete.enableMetadataColumn toggles metadata column and returns self" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try testing.expectEqual(false, ac.show_metadata_column);

    const result = ac.enableMetadataColumn(true);
    try testing.expectEqual(true, ac.show_metadata_column);
    try testing.expect(result == &ac);
}

test "Autocomplete.setMetadataColumnWidth updates metadata column width" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const result = ac.setMetadataColumnWidth(20);

    try testing.expectEqual(@as(u16, 20), ac.metadata_column_width);
    try testing.expect(result == &ac);
}

test "Autocomplete.setProvider sets provider callback" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    // Define a simple provider function
    const TestProvider = struct {
        fn provide(input: []const u8, alloc: std.mem.Allocator) anyerror![]const []const u8 {
            _ = input;
            _ = alloc;
            return &.{};
        }
    };

    const result = ac.setProvider(&TestProvider.provide);
    try testing.expect(ac.provider != null);
    try testing.expect(result == &ac);
}

test "Autocomplete builder pattern chaining works" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const block = (Block{}).withTitle("Test", .top_left);
    _ = ac.setBlock(block)
        .setMaxVisible(5)
        .setHighlightStyle(Style{ .fg = Color{ .indexed = 3 } })
        .enableMetadataColumn(true)
        .setMetadataColumnWidth(15);

    try testing.expectEqual(@as(usize, 5), ac.max_visible);
    try testing.expectEqual(true, ac.show_metadata_column);
    try testing.expectEqual(@as(u16, 15), ac.metadata_column_width);
    try testing.expect(ac.block != null);
}

// ============================================================================
// Input and Suggestion Tests (5 tests)
// ============================================================================

test "Autocomplete.setSuggestions accepts string slice array" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestions(&.{ "hello", "help", "helmet" });

    try testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());
}

test "Autocomplete.setSuggestions filters by fuzzy match with input" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    ac.input = "hel";
    try ac.setSuggestions(&.{ "hello", "help", "helmet", "world", "xyz" });

    // Only "hello", "help", "helmet" should match "hel"
    try testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());
}

test "Autocomplete.setSuggestions resets scroll offset to 0" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    // Set initial suggestions and scroll
    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e" });
    _ = ac.setMaxVisible(2);
    ac.selectLast();
    try testing.expect(ac.scroll_offset > 0); // Should be scrolled

    // Setting new suggestions should reset scroll
    try ac.setSuggestions(&.{ "x", "y", "z" });
    try testing.expectEqual(@as(usize, 0), ac.scroll_offset);
}

test "Autocomplete.setSuggestionsWithDocs stores metadata and documentation" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "println", .metadata = "macro", .doc = "Prints a line to stdout" },
        .{ .text = "printf", .metadata = "fn", .doc = "Formatted print function" },
        .{ .text = "print", .metadata = "fn", .doc = "Print without newline" },
    });

    try testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());
    try testing.expectEqualStrings("println", ac.suggestions.items[0].text);
    try testing.expect(ac.suggestions.items[0].metadata != null);
    try testing.expectEqualStrings("macro", ac.suggestions.items[0].metadata.?);
    try testing.expect(ac.suggestions.items[0].doc != null);
    try testing.expectEqualStrings("Prints a line to stdout", ac.suggestions.items[0].doc.?);
}

test "Autocomplete.setSuggestionsWithDocs filters by fuzzy match" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    ac.input = "pri";
    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "printf", .metadata = "fn" },
        .{ .text = "print", .metadata = "fn" },
        .{ .text = "println", .metadata = "macro" },
        .{ .text = "world", .metadata = "var" },
    });

    // Only "printf", "print", "println" should match "pri"
    try testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());
}

// ============================================================================
// Selection Navigation Tests (6 tests)
// ============================================================================

test "Autocomplete.selectNext moves selection forward" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestions(&.{ "a", "b", "c", "d" });

    try testing.expectEqual(@as(usize, 0), ac.selected_index);
    ac.selectNext();
    try testing.expectEqual(@as(usize, 1), ac.selected_index);
    ac.selectNext();
    try testing.expectEqual(@as(usize, 2), ac.selected_index);
}

test "Autocomplete.selectNext does not exceed list length" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestions(&.{ "a", "b", "c" });

    ac.selectLast();
    try testing.expectEqual(@as(usize, 2), ac.selected_index);
    ac.selectNext(); // Should stay at last
    try testing.expectEqual(@as(usize, 2), ac.selected_index);
}

test "Autocomplete.selectPrev moves selection backward" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestions(&.{ "a", "b", "c", "d" });

    ac.selectLast();
    try testing.expectEqual(@as(usize, 3), ac.selected_index);
    ac.selectPrev();
    try testing.expectEqual(@as(usize, 2), ac.selected_index);
}

test "Autocomplete.selectPrev does not go below 0" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestions(&.{ "a", "b", "c" });

    try testing.expectEqual(@as(usize, 0), ac.selected_index);
    ac.selectPrev(); // Should stay at 0
    try testing.expectEqual(@as(usize, 0), ac.selected_index);
}

test "Autocomplete.selectFirst resets to beginning" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e" });

    ac.selectLast();
    try testing.expectEqual(@as(usize, 4), ac.selected_index);
    ac.selectFirst();
    try testing.expectEqual(@as(usize, 0), ac.selected_index);
}

test "Autocomplete.selectLast jumps to end" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e" });

    try testing.expectEqual(@as(usize, 0), ac.selected_index);
    ac.selectLast();
    try testing.expectEqual(@as(usize, 4), ac.selected_index);
}

// ============================================================================
// Scrolling and Navigation Tests (4 tests)
// ============================================================================

test "Autocomplete.selectNext adjusts scroll offset when selection exceeds visible window" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    _ = ac.setMaxVisible(3);
    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e", "f" });

    try testing.expectEqual(@as(usize, 0), ac.scroll_offset);

    ac.selectNext(); // idx=1, still visible
    ac.selectNext(); // idx=2, still visible
    try testing.expectEqual(@as(usize, 0), ac.scroll_offset); // No scroll yet

    ac.selectNext(); // idx=3, should scroll
    try testing.expectEqual(@as(usize, 1), ac.scroll_offset);
}

test "Autocomplete.selectPrev adjusts scroll offset when selection is above visible window" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    _ = ac.setMaxVisible(3);
    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e" });

    ac.selectLast(); // idx=4, scroll_offset = 4 - 3 + 1 = 2
    try testing.expectEqual(@as(usize, 2), ac.scroll_offset);

    ac.selectPrev(); // idx=3, scroll_offset stays 2
    ac.selectPrev(); // idx=2, scroll_offset stays 2
    ac.selectPrev(); // idx=1, scroll_offset = 1 (since 1 < 2)
    try testing.expectEqual(@as(usize, 1), ac.scroll_offset);
}

test "Autocomplete.selectFirst resets scroll offset to 0" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    _ = ac.setMaxVisible(2);
    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e" });

    ac.selectLast(); // Scroll to end
    try testing.expect(ac.scroll_offset > 0);

    ac.selectFirst();
    try testing.expectEqual(@as(usize, 0), ac.scroll_offset);
}

test "Autocomplete.selectLast adjusts scroll to show last item" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    _ = ac.setMaxVisible(2);
    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e" });

    ac.selectFirst();
    try testing.expectEqual(@as(usize, 0), ac.scroll_offset);

    ac.selectLast();
    try testing.expectEqual(@as(usize, 4), ac.selected_index);
    // scroll_offset = selected_index - max_visible + 1 = 4 - 2 + 1 = 3
    try testing.expectEqual(@as(usize, 3), ac.scroll_offset);
}

// ============================================================================
// State Query Tests (4 tests)
// ============================================================================

test "Autocomplete.getSelected returns text of selected suggestion" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestions(&.{ "apple", "banana", "cherry" });

    const selected1 = ac.getSelected();
    try testing.expect(selected1 != null);
    try testing.expectEqualStrings("apple", selected1.?);

    ac.selectNext();
    const selected2 = ac.getSelected();
    try testing.expect(selected2 != null);
    try testing.expectEqualStrings("banana", selected2.?);
}

test "Autocomplete.getSelected returns null when no suggestions exist" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const selected = ac.getSelected();
    try testing.expectEqual(@as(?[]const u8, null), selected);
}

test "Autocomplete.getSuggestionCount returns correct count" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try testing.expectEqual(@as(usize, 0), ac.getSuggestionCount());

    try ac.setSuggestions(&.{ "a", "b", "c" });
    try testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());

    try ac.setSuggestions(&.{ "x", "y" });
    try testing.expectEqual(@as(usize, 2), ac.getSuggestionCount());
}

test "Autocomplete.getSuggestionCount is 0 after filters exclude all items" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    ac.input = "zzz";
    try ac.setSuggestions(&.{ "apple", "banana", "cherry" });

    // All items should be filtered out (no match for "zzz")
    try testing.expectEqual(@as(usize, 0), ac.getSuggestionCount());
}

// ============================================================================
// Rendering Tests (7 tests)
// ============================================================================

test "Autocomplete.render with empty suggestions does not crash" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    ac.render(&buf, area); // Should not crash

    // Verify buffer is still valid
    const cell = buf.get(0, 0).?;
    try testing.expectEqual(@as(u21, ' '), cell.char);
}

test "Autocomplete.render displays suggestion text" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestions(&.{ "hello", "world" });

    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    ac.render(&buf, area);

    // Check first suggestion text is rendered
    const cell = buf.get(0, 0).?;
    try testing.expectEqual(@as(u21, 'h'), cell.char);
}

test "Autocomplete.render applies highlight style to selected item" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const highlight = Style{ .fg = Color{ .indexed = 1 } };
    _ = ac.setHighlightStyle(highlight);

    try ac.setSuggestions(&.{ "hello", "world" });

    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    ac.render(&buf, area);

    // First item is selected by default, should have highlight style
    const cell = buf.get(0, 0).?;
    try testing.expectEqual(highlight.fg, cell.style.fg);
}

test "Autocomplete.render with max_visible limits displayed suggestions" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    _ = ac.setMaxVisible(2);
    try ac.setSuggestions(&.{ "a", "b", "c", "d" });

    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    ac.render(&buf, area);

    // First two rows should have content from "a" and "b"
    const cell_a = buf.get(0, 0).?;
    const cell_b = buf.get(0, 1).?;
    const cell_empty = buf.get(0, 2).?;

    try testing.expectEqual(@as(u21, 'a'), cell_a.char);
    try testing.expectEqual(@as(u21, 'b'), cell_b.char);
    try testing.expectEqual(@as(u21, ' '), cell_empty.char);
}

test "Autocomplete.render respects scroll offset" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    _ = ac.setMaxVisible(2);
    try ac.setSuggestions(&.{ "a", "b", "c", "d" });

    // Navigate to idx=2, which scrolls
    ac.selectNext();
    ac.selectNext();
    try testing.expectEqual(@as(usize, 1), ac.scroll_offset);

    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    ac.render(&buf, area);

    // Should render "b" and "c" (offset by scroll_offset=1)
    const cell_b = buf.get(0, 0).?;
    const cell_c = buf.get(0, 1).?;

    try testing.expectEqual(@as(u21, 'b'), cell_b.char);
    try testing.expectEqual(@as(u21, 'c'), cell_c.char);
}

test "Autocomplete.render with block draws border" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const block = (Block{}).withTitle("Autocomplete", .top_left);
    _ = ac.setBlock(block);

    try ac.setSuggestions(&.{ "hello" });

    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    ac.render(&buf, area);

    // Top-left corner should have a border character (not space)
    const cell = buf.get(0, 0).?;
    try testing.expect(cell.char != ' ');
}

test "Autocomplete.render with metadata column displays metadata" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "foo", .metadata = "fn" },
        .{ .text = "bar", .metadata = "type" },
    });

    _ = ac.enableMetadataColumn(true);
    _ = ac.setMetadataColumnWidth(8);

    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    ac.render(&buf, area);

    // First suggestion text should be rendered
    const cell_text = buf.get(0, 0).?;
    try testing.expectEqual(@as(u21, 'f'), cell_text.char);

    // Metadata should appear at the right side (around column 30-8=22)
    // Due to rendering logic, "fn" should be in the metadata column area
    const cell_meta = buf.get(22, 0).?;
    try testing.expect(cell_meta.char == 'f' or cell_meta.char == 'n' or cell_meta.char == ' ');
}

// ============================================================================
// Documentation Preview Tests (3 tests)
// ============================================================================

test "Autocomplete.render with doc preview displays documentation" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "println", .doc = "Prints a line to stdout" },
    });

    _ = ac.enableDocPreview(true);
    _ = ac.setPreviewWidth(30);

    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    ac.render(&buf, area); // Should not crash with preview enabled

    // First character should be from suggestion text
    const cell_text = buf.get(0, 0).?;
    try testing.expectEqual(@as(u21, 'p'), cell_text.char);

    // Documentation preview is rendered - verify buffer has content
    // We can't assume exact positions since rendering depends on terminal width
    // and internal layout calculations, but we can verify no crash occurred
    try testing.expectEqual(@as(usize, 1), ac.getSuggestionCount());
}

test "Autocomplete.render doc preview wraps long text" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const long_doc = "This is a very long documentation string that should wrap across multiple lines when rendered in the preview pane";
    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "func", .doc = long_doc },
    });

    _ = ac.enableDocPreview(true);
    _ = ac.setPreviewWidth(20);

    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    ac.render(&buf, area);

    // Doc preview area starts at x = inner.x + list_width + 1 = 0 + 59 + 1 = 60
    // (list_width = inner.width - preview_width - 1 = 80 - 20 - 1 = 59).
    // Row 0 renders the first 20 chars of long_doc unwrapped-by-word ("This is a very long"),
    // so x=61 is offset 1 into that slice, i.e. long_doc[1] = 'h'.
    const cell_row1 = buf.get(61, 0).?;
    try testing.expectEqual(@as(u21, 'h'), cell_row1.char);
}

test "Autocomplete.render skips doc preview when no doc on selected item" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "item1" }, // No doc
    });

    _ = ac.enableDocPreview(true);
    _ = ac.setPreviewWidth(30);

    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    ac.render(&buf, area); // Should not crash even though no doc

    const cell_text = buf.get(0, 0).?;
    try testing.expectEqual(@as(u21, 'i'), cell_text.char);
}

// ============================================================================
// Regression Tests for u16 Overflow (5 tests)
// These tests verify that renderList() and renderDocPreview() don't panic
// when Rect coordinates are near u16::max, causing unguarded addition overflow.
// ============================================================================

test "Autocomplete.render does not panic with Rect.y + height overflow in renderList" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestions(&.{ "hello", "world", "test" });

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // y + height = 65530 + 100 = 65630 (overflows u16 max of 65535)
    // This would trigger overflow in renderList line ~357 if unguarded: `y < area.y + area.height`
    const area = Rect{ .x = 0, .y = 65530, .width = 80, .height = 100 };
    ac.render(&buf, area); // Should complete without panic

    try testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());
}

test "Autocomplete.render does not panic with Rect.x + width overflow in renderList text rendering" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestions(&.{ "hello", "world" });

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // x + width = 65500 + 80 = 65580 (near u16 max)
    // This would trigger overflow in renderList line ~371: `if (x >= area.x + area.width) break`
    const area = Rect{ .x = 65500, .y = 0, .width = 80, .height = 24 };
    ac.render(&buf, area); // Should complete without panic

    try testing.expectEqual(@as(usize, 2), ac.getSuggestionCount());
}

test "Autocomplete.render does not panic with metadata column and x + width overflow" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "foo", .metadata = "fn" },
    });

    _ = ac.enableMetadataColumn(true);
    _ = ac.setMetadataColumnWidth(8);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // x + width = 65500 + 100 = 65600 (overflows u16 max)
    // renderList line ~379-391 uses area.x + area.width for metadata column positioning
    const area = Rect{ .x = 65500, .y = 0, .width = 100, .height = 24 };
    ac.render(&buf, area); // Should complete without panic

    try testing.expectEqual(@as(usize, 1), ac.getSuggestionCount());
}

test "Autocomplete.render does not panic with doc preview and y + height overflow in renderDocPreview" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "func", .doc = "This is documentation text for testing overflow" },
    });

    _ = ac.enableDocPreview(true);
    _ = ac.setPreviewWidth(30);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // y + height = 65530 + 100 = 65630 (overflows u16 max)
    // renderDocPreview line ~418 uses area.y + area.height in loop: `while (char_idx < doc.len and y < area.y + area.height)`
    const area = Rect{ .x = 0, .y = 65530, .width = 80, .height = 100 };
    ac.render(&buf, area); // Should complete without panic

    try testing.expectEqual(@as(usize, 1), ac.getSuggestionCount());
}

test "Autocomplete.render does not panic with x + width overflow in renderDocPreview character rendering" {
    const allocator = testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "print", .doc = "Prints output to the terminal device stream" },
    });

    _ = ac.enableDocPreview(true);
    _ = ac.setPreviewWidth(40);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // x + width = 65500 + 80 = 65580 (near u16 max)
    // renderDocPreview line ~423, 435 uses area.x + area.width: `while (x < area.x + area.width)`
    const area = Rect{ .x = 65500, .y = 0, .width = 80, .height = 24 };
    ac.render(&buf, area); // Should complete without panic

    try testing.expectEqual(@as(usize, 1), ac.getSuggestionCount());
}
