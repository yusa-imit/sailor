//! Autocomplete widget: suggestion list with fuzzy matching and keyboard navigation.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = @import("../buffer.zig").Buffer;
const Cell = @import("../buffer.zig").Cell;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;
const assert = std.debug.assert;

/// Autocomplete widget for displaying suggestion lists with fuzzy matching
///
/// Features:
/// - Fuzzy matching with score-based ranking
/// - Keyboard navigation (up/down, home/end, Tab, Ctrl+Space)
/// - Selected item highlighting
/// - Max visible items with scrolling
/// - Multi-column layout with optional metadata columns
/// - Documentation preview pane for selected item
/// - Custom provider callback for dynamic suggestions
/// - Optional block borders
///
/// Example (basic):
/// ```zig
/// var autocomplete = Autocomplete.init(allocator);
/// defer autocomplete.deinit();
///
/// try autocomplete.setInput("hel");
/// try autocomplete.setSuggestions(&.{ "hello", "help", "helmet" });
/// autocomplete.setMaxVisible(5);
/// autocomplete.selectNext(); // Navigate down
/// const selected = autocomplete.getSelected(); // Returns "hello"
///
/// autocomplete.render(buffer, area);
/// ```
///
/// Example (with documentation):
/// ```zig
/// var autocomplete = Autocomplete.init(allocator);
/// defer autocomplete.deinit();
///
/// try autocomplete.setSuggestionsWithDocs(&.{
///     .{ .text = "println", .doc = "Prints a line to stdout", .metadata = "macro" },
///     .{ .text = "printf", .doc = "Formatted print", .metadata = "fn" },
/// });
/// autocomplete.enableDocPreview(true);
/// autocomplete.setPreviewWidth(40); // 40 columns for preview pane
///
/// autocomplete.render(buffer, area); // Splits area: list | preview
/// ```
pub const Autocomplete = struct {
    allocator: Allocator,
    input: []const u8,
    suggestions: ArrayList(Suggestion),
    selected_index: usize,
    scroll_offset: usize,
    max_visible: usize,
    block: ?Block,
    highlight_style: Style,
    normal_style: Style,
    metadata_style: Style,
    doc_style: Style,
    provider: ?*const ProviderFn,
    show_doc_preview: bool,
    preview_width: u16,
    show_metadata_column: bool,
    metadata_column_width: u16,

    /// Suggestion item with optional metadata and documentation
    pub const Suggestion = struct {
        text: []const u8,
        score: f32 = 1.0,
        metadata: ?[]const u8 = null, // e.g., type annotation, file path
        doc: ?[]const u8 = null, // documentation preview text
    };

    /// Simple suggestion item for basic use cases (backward compatible)
    pub const SuggestionItem = struct {
        text: []const u8,
        metadata: ?[]const u8 = null,
        doc: ?[]const u8 = null,
    };

    pub const ProviderFn = fn (input: []const u8, allocator: Allocator) anyerror![]const []const u8;

    /// Initializes an Autocomplete widget with default settings.
    /// The returned instance must be freed with `.deinit()`.
    /// Default configuration: 10 max visible items, black-on-white highlight style.
    pub fn init(allocator: Allocator) Autocomplete {
        return .{
            .allocator = allocator,
            .input = "",
            .suggestions = ArrayList(Suggestion).empty,
            .selected_index = 0,
            .scroll_offset = 0,
            .max_visible = 10,
            .block = null,
            .highlight_style = Style{ .fg = Color{ .indexed = 0 }, .bg = Color{ .indexed = 7 } },
            .normal_style = Style{},
            .metadata_style = Style{ .fg = Color{ .indexed = 8 } }, // gray
            .doc_style = Style{ .fg = Color{ .indexed = 7 } }, // white
            .provider = null,
            .show_doc_preview = false,
            .preview_width = 40,
            .show_metadata_column = false,
            .metadata_column_width = 10,
        };
    }

    /// Frees resources associated with this autocomplete widget.
    /// Clears the internal suggestions list.
    pub fn deinit(self: *Autocomplete) void {
        self.suggestions.deinit(self.allocator);
    }

    /// Sets the optional border block around the autocomplete list.
    /// Returns `self` for method chaining.
    pub fn setBlock(self: *Autocomplete, block: Block) *Autocomplete {
        self.block = block;
        return self;
    }

    /// Sets the maximum number of visible suggestions in the list.
    /// If more suggestions exist, the list will scroll.
    /// Returns `self` for method chaining.
    pub fn setMaxVisible(self: *Autocomplete, max: usize) *Autocomplete {
        self.max_visible = max;
        self.clampScroll();
        self.check_invariants();
        return self;
    }

    /// Asserts the selection/scroll invariants: the selection is in range and inside the visible
    /// window, and the window never starts past the selection. Cheap (O(1)).
    pub fn check_invariants(self: *const Autocomplete) void {
        const len = self.suggestions.items.len;
        if (len == 0) {
            assert(self.selected_index == 0);
            assert(self.scroll_offset == 0);
            return;
        }
        assert(self.selected_index < len);
        assert(self.scroll_offset <= self.selected_index);
        assert(self.selected_index < self.scroll_offset + self.windowSize());
    }

    /// Number of rows the scroll logic keeps the selection inside (at least 1).
    fn windowSize(self: *const Autocomplete) usize {
        return @max(self.max_visible, 1);
    }

    /// Re-establishes the scroll invariants after `max_visible` changed: no blank rows below the
    /// last item when the window can show more, and the selection stays inside the window.
    fn clampScroll(self: *Autocomplete) void {
        const len = self.suggestions.items.len;
        if (len == 0) {
            self.scroll_offset = 0;
            return;
        }
        const window = self.windowSize();
        self.scroll_offset = @min(self.scroll_offset, len -| window);
        self.scroll_offset = @min(self.scroll_offset, self.selected_index);
        if (self.selected_index >= self.scroll_offset + window) {
            self.scroll_offset = self.selected_index - window + 1;
        }
    }

    /// Sets the style applied to the currently selected suggestion.
    /// Returns `self` for method chaining.
    pub fn setHighlightStyle(self: *Autocomplete, style: Style) *Autocomplete {
        self.highlight_style = style;
        return self;
    }

    /// Sets the style applied to non-selected suggestions.
    /// Returns `self` for method chaining.
    pub fn setNormalStyle(self: *Autocomplete, style: Style) *Autocomplete {
        self.normal_style = style;
        return self;
    }

    /// Sets the dynamic suggestion provider function.
    /// The provider is called automatically when input changes via `setInput()`.
    /// Returns `self` for method chaining.
    pub fn setProvider(self: *Autocomplete, provider: *const ProviderFn) *Autocomplete {
        self.provider = provider;
        return self;
    }

    /// Enable or disable documentation preview pane
    /// When enabled, splits the render area into list | preview
    /// Returns `self` for method chaining.
    pub fn enableDocPreview(self: *Autocomplete, enable: bool) *Autocomplete {
        self.show_doc_preview = enable;
        return self;
    }

    /// Set width of documentation preview pane (in columns)
    /// Returns `self` for method chaining.
    pub fn setPreviewWidth(self: *Autocomplete, width: u16) *Autocomplete {
        self.preview_width = width;
        return self;
    }

    /// Enable or disable metadata column (e.g., type annotations)
    /// Returns `self` for method chaining.
    pub fn enableMetadataColumn(self: *Autocomplete, enable: bool) *Autocomplete {
        self.show_metadata_column = enable;
        return self;
    }

    /// Set width of metadata column (in columns)
    /// Returns `self` for method chaining.
    pub fn setMetadataColumnWidth(self: *Autocomplete, width: u16) *Autocomplete {
        self.metadata_column_width = width;
        return self;
    }

    /// Set style for metadata column text
    /// Returns `self` for method chaining.
    pub fn setMetadataStyle(self: *Autocomplete, style: Style) *Autocomplete {
        self.metadata_style = style;
        return self;
    }

    /// Set style for documentation preview text
    /// Returns `self` for method chaining.
    pub fn setDocStyle(self: *Autocomplete, style: Style) *Autocomplete {
        self.doc_style = style;
        return self;
    }

    /// Set input text and trigger suggestion update
    pub fn setInput(self: *Autocomplete, input: []const u8) !void {
        self.input = input;
        try self.updateSuggestions();
    }

    /// Manually set suggestions (bypasses provider) - backward compatible
    pub fn setSuggestions(self: *Autocomplete, items: []const []const u8) !void {
        self.suggestions.clearRetainingCapacity();
        for (items) |item| {
            const score = fuzzyMatch(self.input, item);
            if (score > 0.0) {
                try self.suggestions.append(self.allocator, .{ .text = item, .score = score });
            }
        }
        // Sort by score descending
        std.mem.sort(Suggestion, self.suggestions.items, {}, suggestionLessThan);
        self.selected_index = 0;
        self.scroll_offset = 0;
        self.check_invariants();
    }

    /// Set suggestions with metadata and documentation
    pub fn setSuggestionsWithDocs(self: *Autocomplete, items: []const SuggestionItem) !void {
        self.suggestions.clearRetainingCapacity();
        for (items) |item| {
            const score = fuzzyMatch(self.input, item.text);
            if (score > 0.0) {
                try self.suggestions.append(self.allocator, .{
                    .text = item.text,
                    .score = score,
                    .metadata = item.metadata,
                    .doc = item.doc,
                });
            }
        }
        // Sort by score descending
        std.mem.sort(Suggestion, self.suggestions.items, {}, suggestionLessThan);
        self.selected_index = 0;
        self.scroll_offset = 0;
        self.check_invariants();
    }

    fn updateSuggestions(self: *Autocomplete) !void {
        if (self.provider) |provider| {
            const items = try provider(self.input, self.allocator);
            defer self.allocator.free(items);
            try self.setSuggestions(items);
        }
    }

    /// Moves selection down to the next suggestion.
    /// If at the end of the list, selection remains on the last item.
    /// Automatically adjusts scroll offset to keep selection visible.
    pub fn selectNext(self: *Autocomplete) void {
        if (self.suggestions.items.len == 0) return;
        if (self.selected_index + 1 < self.suggestions.items.len) {
            self.selected_index += 1;
            // Scroll down if selected item is below visible window
            const window = self.windowSize();
            if (self.selected_index >= self.scroll_offset + window) {
                self.scroll_offset = self.selected_index - window + 1;
            }
        }
        self.check_invariants();
    }

    /// Moves selection up to the previous suggestion.
    /// If at the beginning of the list, selection remains on the first item.
    /// Automatically adjusts scroll offset to keep selection visible.
    pub fn selectPrev(self: *Autocomplete) void {
        if (self.suggestions.items.len == 0) return;
        if (self.selected_index > 0) {
            self.selected_index -= 1;
            // Scroll up if selected item is above visible window
            if (self.selected_index < self.scroll_offset) {
                self.scroll_offset = self.selected_index;
            }
        }
        self.check_invariants();
    }

    /// Jumps selection to the first suggestion and resets scroll to the top.
    pub fn selectFirst(self: *Autocomplete) void {
        self.selected_index = 0;
        self.scroll_offset = 0;
        self.check_invariants();
    }

    /// Jumps selection to the last suggestion and adjusts scroll to make it visible.
    pub fn selectLast(self: *Autocomplete) void {
        if (self.suggestions.items.len == 0) return;
        self.selected_index = self.suggestions.items.len - 1;
        const window = self.windowSize();
        if (self.selected_index >= window) {
            self.scroll_offset = self.selected_index - window + 1;
        }
        self.check_invariants();
    }

    /// Returns the text of the currently selected suggestion, or `null` if no suggestions exist.
    pub fn getSelected(self: *const Autocomplete) ?[]const u8 {
        if (self.suggestions.items.len == 0) return null;
        if (self.selected_index >= self.suggestions.items.len) return null;
        return self.suggestions.items[self.selected_index].text;
    }

    /// Returns the total number of suggestions currently available.
    pub fn getSuggestionCount(self: *const Autocomplete) usize {
        return self.suggestions.items.len;
    }

    /// Renders the autocomplete suggestion list to the given buffer within the specified area.
    /// Displays suggestions with fuzzy match scoring, highlights the selected item,
    /// supports scrolling, multi-column layout, and documentation preview pane.
    pub fn render(self: *const Autocomplete, buf: *Buffer, area: Rect) void {
        const inner = if (self.block) |b| b.inner(area) else area;

        // Render block border if present
        if (self.block) |b| {
            b.render(buf, area);
        }

        if (self.suggestions.items.len == 0) {
            return; // No suggestions to render
        }

        // Split area if doc preview is enabled
        var list_area = inner;
        var preview_area: ?Rect = null;

        if (self.show_doc_preview and inner.width > self.preview_width +| 2) {
            const list_width = inner.width - self.preview_width - 1; // -1 for separator
            const sep_x = inner.x +| list_width;

            list_area = Rect{
                .x = inner.x,
                .y = inner.y,
                .width = list_width,
                .height = inner.height,
            };
            preview_area = Rect{
                .x = sep_x +| 1,
                .y = inner.y,
                .width = self.preview_width,
                .height = inner.height,
            };

            // Render separator between list and preview
            const sep = Rect{ .x = sep_x, .y = inner.y, .width = 1, .height = inner.height };
            buf.fill(sep, '│', self.normal_style);
        }

        self.renderList(buf, list_area);
        if (preview_area) |parea| {
            self.renderDocPreview(buf, parea);
        }
    }

    fn renderList(self: *const Autocomplete, buf: *Buffer, area: Rect) void {
        const len = self.suggestions.items.len;
        assert(self.scroll_offset <= len);
        const end_index = @min(self.scroll_offset + @min(self.max_visible, len), len);
        assert(end_index >= self.scroll_offset);
        const area_bottom = area.y +| area.height;

        var y: u16 = area.y;
        for (self.suggestions.items[self.scroll_offset..end_index], 0..) |suggestion, i| {
            if (y >= area_bottom) break;
            const is_selected = (self.scroll_offset + i) == self.selected_index;
            const style = if (is_selected) self.highlight_style else self.normal_style;
            buf.fill(.{ .x = area.x, .y = y, .width = area.width, .height = 1 }, ' ', style);
            self.renderRow(buf, area, y, suggestion, is_selected);
            y += 1; // y < area_bottom <= maxInt(u16) here.
        }
    }

    /// Draws one suggestion row over an already background-filled row. Text and metadata are cut
    /// by terminal cells, never in the middle of a UTF-8 sequence or a wide character.
    fn renderRow(
        self: *const Autocomplete,
        buf: *Buffer,
        area: Rect,
        y: u16,
        suggestion: Suggestion,
        is_selected: bool,
    ) void {
        assert(y >= area.y);
        const style = if (is_selected) self.highlight_style else self.normal_style;
        const meta = if (self.show_metadata_column) suggestion.metadata else null;
        const text_cells: usize = if (meta != null)
            area.width -| self.metadata_column_width -| 1
        else
            area.width;
        const text_bytes = UnicodeWidth.truncate(suggestion.text, text_cells);
        buf.setString(area.x, y, suggestion.text[0..text_bytes], style);

        const meta_text = meta orelse return;
        const area_right = area.x +| area.width;
        const meta_x = @max(area.x, area_right -| self.metadata_column_width);
        const meta_bytes = UnicodeWidth.truncate(meta_text, area_right - meta_x);
        const meta_style = if (is_selected)
            Style{ .fg = self.metadata_style.fg, .bg = self.highlight_style.bg }
        else
            self.metadata_style;
        buf.setString(meta_x, y, meta_text[0..meta_bytes], meta_style);
    }

    /// One wrapped row of documentation: `draw` bytes are shown, `consumed` bytes are used up
    /// (the difference is the space or the skipped character at the break).
    const DocSegment = struct { draw: usize, consumed: usize };

    /// Splits the next row off `rest` (which holds no newline) for a row `width` cells wide:
    /// breaks at the last space that fits, else hard-breaks at the cell limit.
    fn nextDocSegment(rest: []const u8, width: u16) DocSegment {
        assert(width > 0);
        assert(std.mem.indexOfScalar(u8, rest, '\n') == null);
        const fit = UnicodeWidth.truncate(rest, width);
        if (fit == rest.len) return .{ .draw = fit, .consumed = fit };
        if (rest[fit] == ' ') return .{ .draw = fit, .consumed = fit + 1 };
        if (std.mem.lastIndexOfScalar(u8, rest[0..fit], ' ')) |space| {
            if (space > 0) return .{ .draw = space, .consumed = space + 1 };
        }
        if (fit == 0) {
            // The first character is wider than the area: skip it so the text still advances.
            const skip = std.unicode.utf8ByteSequenceLength(rest[0]) catch 1;
            return .{ .draw = 0, .consumed = @min(skip, rest.len) };
        }
        return .{ .draw = fit, .consumed = fit };
    }

    fn renderDocPreview(self: *const Autocomplete, buf: *Buffer, area: Rect) void {
        if (self.selected_index >= self.suggestions.items.len) return;
        const doc = self.suggestions.items[self.selected_index].doc orelse return;
        if (area.width == 0) return;

        const area_bottom = area.y +| area.height;
        var y: u16 = area.y;
        var lines = std.mem.splitScalar(u8, doc, '\n');
        while (lines.next()) |line| {
            var rest = line;
            // Every logical line (even an empty one) takes at least one row.
            while (y < area_bottom) {
                const seg = nextDocSegment(rest, area.width);
                const row = Rect{ .x = area.x, .y = y, .width = area.width, .height = 1 };
                buf.fill(row, ' ', self.doc_style);
                buf.setString(area.x, y, rest[0..seg.draw], self.doc_style);
                y += 1; // y < area_bottom <= maxInt(u16) here.
                rest = rest[seg.consumed..];
                if (rest.len == 0) break;
            }
            if (y >= area_bottom) return;
        }
    }

    fn suggestionLessThan(_: void, a: Suggestion, b: Suggestion) bool {
        return a.score > b.score; // Descending order (higher score first)
    }

    /// Fuzzy matching algorithm with score calculation
    fn fuzzyMatch(input: []const u8, candidate: []const u8) f32 {
        if (input.len == 0) return 1.0; // Empty input matches everything

        var score: f32 = 0.0;
        var input_idx: usize = 0;
        var last_match_idx: ?usize = null;

        for (candidate, 0..) |c, i| {
            if (input_idx >= input.len) break;

            const input_char = std.ascii.toLower(input[input_idx]);
            const candidate_char = std.ascii.toLower(c);

            if (input_char == candidate_char) {
                // Consecutive match bonus
                const consecutive_bonus: f32 = if (last_match_idx) |last|
                    if (i == last + 1) 0.2 else 0.0
                else
                    0.0;
                // Start-of-word bonus
                const word_start = i == 0 or !std.ascii.isAlphanumeric(candidate[i - 1]);
                const start_bonus: f32 = if (word_start) 0.1 else 0.0;
                score += 1.0 + consecutive_bonus + start_bonus;
                last_match_idx = i;
                input_idx += 1;
            }
        }

        // All input characters must match
        if (input_idx < input.len) return 0.0;

        // Normalize by candidate length (prefer shorter matches). The penalty is capped below the
        // 1.0 every matched character earns, so a long candidate still counts as a match.
        const length_penalty = @min(@as(f32, @floatFromInt(candidate.len)) / 100.0, 0.5);
        assert(score >= 1.0);
        return score - length_penalty;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

const highlight = Style{ .fg = Color{ .indexed = 0 }, .bg = Color{ .indexed = 7 } };

/// Assert every buffer row equals the expected text, one codepoint per cell.
fn expectRows(buf: Buffer, rows: []const []const u8) !void {
    try testing.expectEqual(@as(usize, buf.height), rows.len);
    for (rows, 0..) |row, y| {
        var view = try std.unicode.Utf8View.init(row);
        var it = view.iterator();
        var x: u16 = 0;
        while (it.nextCodepoint()) |cp| : (x += 1) {
            try testing.expectEqual(cp, buf.getChar(x, @intCast(y)));
        }
        try testing.expectEqual(buf.width, x);
    }
}

/// Assert cells x0..x1 (exclusive) of row y all carry `style`.
fn expectRowStyle(buf: Buffer, y: u16, x0: u16, x1: u16, style: Style) !void {
    var x = x0;
    while (x < x1) : (x += 1) try testing.expectEqual(style, buf.getStyle(x, y));
}

fn fullArea(buf: Buffer) Rect {
    return .{ .x = 0, .y = 0, .width = buf.width, .height = buf.height };
}

fn prefixProvider(input: []const u8, allocator: Allocator) anyerror![]const []const u8 {
    const words = [_][]const u8{ "apple", "apricot", "banana" };
    var out = ArrayList([]const u8).empty;
    errdefer out.deinit(allocator);
    for (words) |word| {
        if (std.mem.startsWith(u8, word, input)) try out.append(allocator, word);
    }
    return out.toOwnedSlice(allocator);
}

fn failingProvider(input: []const u8, allocator: Allocator) anyerror![]const []const u8 {
    _ = input;
    _ = allocator;
    return error.ProviderFailed;
}

test "autocomplete: init has documented defaults and no suggestions" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try testing.expectEqual(@as(usize, 0), ac.selected_index);
    try testing.expectEqual(@as(usize, 0), ac.scroll_offset);
    try testing.expectEqual(@as(usize, 10), ac.max_visible);
    try testing.expectEqual(@as(usize, 0), ac.getSuggestionCount());
    try testing.expectEqual(@as(?[]const u8, null), ac.getSelected());
    try testing.expect(ac.block == null);
    try testing.expect(!ac.show_doc_preview);
    try testing.expect(!ac.show_metadata_column);
    ac.check_invariants();
}

test "autocomplete: empty input keeps every item in the given order" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "hello", "help", "helmet" });
    try testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());
    try testing.expectEqualStrings("hello", ac.suggestions.items[0].text);
    try testing.expectEqualStrings("help", ac.suggestions.items[1].text);
    try testing.expectEqualStrings("helmet", ac.suggestions.items[2].text);
}

test "autocomplete: input filters non-matches and ranks shorter prefix matches first" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    ac.input = "hel";
    try ac.setSuggestions(&.{ "helmet", "world", "hello", "help" });
    try testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());
    try testing.expectEqualStrings("help", ac.suggestions.items[0].text);
    try testing.expectEqualStrings("hello", ac.suggestions.items[1].text);
    try testing.expectEqualStrings("helmet", ac.suggestions.items[2].text);
}

test "autocomplete: input matching nothing leaves an empty list with no selection" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "a", "b" });
    ac.selectNext();
    ac.input = "zzz";
    try ac.setSuggestions(&.{ "a", "b" });
    try testing.expectEqual(@as(usize, 0), ac.getSuggestionCount());
    try testing.expectEqual(@as(?[]const u8, null), ac.getSelected());
    try testing.expectEqual(@as(usize, 0), ac.selected_index);
    ac.check_invariants();
}

test "autocomplete: fuzzy match rejects missing, out-of-order and over-long input" {
    try testing.expectEqual(@as(f32, 0.0), Autocomplete.fuzzyMatch("xyz", "hello"));
    try testing.expectEqual(@as(f32, 0.0), Autocomplete.fuzzyMatch("lh", "hello"));
    try testing.expectEqual(@as(f32, 0.0), Autocomplete.fuzzyMatch("helloo", "hello"));
    try testing.expect(Autocomplete.fuzzyMatch("hlo", "hello") > 0.0);
    try testing.expectEqual(@as(f32, 1.0), Autocomplete.fuzzyMatch("", "anything"));
}

test "autocomplete: fuzzy match prefers consecutive over scattered matches" {
    const consecutive = Autocomplete.fuzzyMatch("hel", "hello");
    const scattered = Autocomplete.fuzzyMatch("hel", "hxeyl");
    try testing.expect(consecutive > scattered);
}

test "autocomplete: fuzzy match does not reward a first match at index 1 as consecutive" {
    // Regression: the exact candidate "e" must outrank "xe" for the input "e".
    try testing.expect(Autocomplete.fuzzyMatch("e", "e") > Autocomplete.fuzzyMatch("e", "xe"));
}

test "autocomplete: fuzzy match is case insensitive in both directions" {
    const base = Autocomplete.fuzzyMatch("hel", "hello");
    try testing.expectEqual(base, Autocomplete.fuzzyMatch("hel", "HELLO"));
    try testing.expectEqual(base, Autocomplete.fuzzyMatch("HEL", "hello"));
    try testing.expectEqual(base, Autocomplete.fuzzyMatch("HeL", "hELLo"));
}

test "autocomplete: very long matching candidates are still matches" {
    // Regression: the length penalty used to push the score below zero past ~110 bytes.
    const long = "a" ** 300;
    try testing.expect(Autocomplete.fuzzyMatch("a", long) > 0.0);
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    ac.input = "a";
    try ac.setSuggestions(&.{long});
    try testing.expectEqual(@as(usize, 1), ac.getSuggestionCount());
}

test "autocomplete: navigation moves by one and stays inside the list" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e" });
    ac.selectNext();
    try testing.expectEqual(@as(usize, 1), ac.selected_index);
    ac.selectNext();
    try testing.expectEqual(@as(usize, 2), ac.selected_index);
    ac.selectPrev();
    try testing.expectEqual(@as(usize, 1), ac.selected_index);
    ac.selectFirst();
    try testing.expectEqual(@as(usize, 0), ac.selected_index);
    ac.selectLast();
    try testing.expectEqual(@as(usize, 4), ac.selected_index);
    try testing.expectEqualStrings("e", ac.getSelected().?);
}

test "autocomplete: navigation clamps at both ends" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "a", "b", "c" });
    ac.selectPrev();
    try testing.expectEqual(@as(usize, 0), ac.selected_index);
    ac.selectLast();
    ac.selectNext();
    try testing.expectEqual(@as(usize, 2), ac.selected_index);
}

test "autocomplete: navigation on an empty list is a no-op" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    ac.selectNext();
    ac.selectPrev();
    ac.selectLast();
    ac.selectFirst();
    try testing.expectEqual(@as(usize, 0), ac.selected_index);
    try testing.expectEqual(@as(usize, 0), ac.scroll_offset);
    try testing.expectEqual(@as(?[]const u8, null), ac.getSelected());
}

test "autocomplete: scroll offset follows the selection down and back up" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    _ = ac.setMaxVisible(3);
    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e", "f" });
    ac.selectNext();
    ac.selectNext();
    try testing.expectEqual(@as(usize, 0), ac.scroll_offset); // idx 2 is still in rows 0..2
    ac.selectNext();
    try testing.expectEqual(@as(usize, 3), ac.selected_index);
    try testing.expectEqual(@as(usize, 1), ac.scroll_offset);
    ac.selectPrev();
    ac.selectPrev();
    try testing.expectEqual(@as(usize, 1), ac.scroll_offset); // idx 1 is the window's first row
    ac.selectPrev();
    try testing.expectEqual(@as(usize, 0), ac.selected_index);
    try testing.expectEqual(@as(usize, 0), ac.scroll_offset);
}

test "autocomplete: selectLast scrolls the last item into the window" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    _ = ac.setMaxVisible(2);
    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e" });
    ac.selectLast();
    try testing.expectEqual(@as(usize, 4), ac.selected_index);
    try testing.expectEqual(@as(usize, 3), ac.scroll_offset);
    ac.selectFirst();
    try testing.expectEqual(@as(usize, 0), ac.scroll_offset);
}

test "autocomplete: shrinking max_visible keeps the selection in the window" {
    // Regression: the scroll offset used to stay put and could hide the selection.
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    _ = ac.setMaxVisible(4);
    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e", "f" });
    ac.selectLast(); // selected 5, scroll 2
    _ = ac.setMaxVisible(1);
    try testing.expectEqual(@as(usize, 5), ac.selected_index);
    try testing.expectEqual(@as(usize, 5), ac.scroll_offset);
}

test "autocomplete: growing max_visible does not leave blank rows below the list" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    _ = ac.setMaxVisible(2);
    try ac.setSuggestions(&.{ "a", "b", "c", "d", "e", "f" });
    ac.selectLast(); // selected 5, scroll 4
    _ = ac.setMaxVisible(5);
    try testing.expectEqual(@as(usize, 1), ac.scroll_offset); // rows b..f
    _ = ac.setMaxVisible(20);
    try testing.expectEqual(@as(usize, 0), ac.scroll_offset);
}

test "autocomplete: max_visible zero never panics and shows nothing" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    _ = ac.setMaxVisible(0);
    try ac.setSuggestions(&.{ "a", "b", "c" });
    ac.selectNext();
    ac.selectLast();
    ac.selectPrev();
    var buf = try Buffer.init(testing.allocator, 4, 3);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "    ", "    ", "    " });
}

test "autocomplete: getSelected follows the selection" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "hello", "world" });
    try testing.expectEqualStrings("hello", ac.getSelected().?);
    ac.selectNext();
    try testing.expectEqualStrings("world", ac.getSelected().?);
}

test "autocomplete: provider is called by setInput and filters the list" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    _ = ac.setProvider(&prefixProvider);
    try ac.setInput("ap");
    try testing.expectEqual(@as(usize, 2), ac.getSuggestionCount());
    try testing.expectEqualStrings("apple", ac.suggestions.items[0].text);
    try testing.expectEqualStrings("apricot", ac.suggestions.items[1].text);
    try ac.setInput("");
    try testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());
    try ac.setInput("zzz");
    try testing.expectEqual(@as(usize, 0), ac.getSuggestionCount());
    try testing.expectEqual(@as(?[]const u8, null), ac.getSelected());
}

test "autocomplete: setInput without a provider only stores the input" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "a", "b" });
    try ac.setInput("zzz");
    try testing.expectEqualStrings("zzz", ac.input);
    try testing.expectEqual(@as(usize, 2), ac.getSuggestionCount());
}

test "autocomplete: provider error propagates and keeps the previous suggestions" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "a", "b" });
    _ = ac.setProvider(&failingProvider);
    try testing.expectError(error.ProviderFailed, ac.setInput("a"));
    try testing.expectEqual(@as(usize, 2), ac.getSuggestionCount());
    ac.check_invariants();
}

test "autocomplete: allocation failure in setSuggestions is returned, not swallowed" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    var ac = Autocomplete.init(failing.allocator());
    defer ac.deinit();
    try testing.expectError(error.OutOfMemory, ac.setSuggestions(&.{"a"}));
    try testing.expectError(error.OutOfMemory, ac.setSuggestionsWithDocs(&.{.{ .text = "a" }}));
}

test "autocomplete: setSuggestionsWithDocs keeps metadata and doc and filters by input" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    ac.input = "prin";
    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "println", .metadata = "macro", .doc = "Prints a line" },
        .{ .text = "write", .metadata = "fn" },
        .{ .text = "print", .metadata = "fn", .doc = "Print" },
    });
    try testing.expectEqual(@as(usize, 2), ac.getSuggestionCount());
    try testing.expectEqualStrings("print", ac.suggestions.items[0].text);
    try testing.expectEqualStrings("fn", ac.suggestions.items[0].metadata.?);
    try testing.expectEqualStrings("println", ac.suggestions.items[1].text);
    try testing.expectEqualStrings("macro", ac.suggestions.items[1].metadata.?);
    try testing.expectEqualStrings("Prints a line", ac.suggestions.items[1].doc.?);
}

test "autocomplete: builders set exactly their own field" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    const meta = Style{ .fg = Color{ .indexed = 3 } };
    const doc = Style{ .fg = Color{ .indexed = 4 } };
    const hl = Style{ .fg = Color{ .indexed = 5 } };
    const normal = Style{ .bold = true };
    _ = ac.setBlock(Block{}).setMaxVisible(5).setHighlightStyle(hl).setNormalStyle(normal)
        .enableDocPreview(true).setPreviewWidth(50).enableMetadataColumn(true)
        .setMetadataColumnWidth(15).setMetadataStyle(meta).setDocStyle(doc);
    try testing.expect(ac.block != null);
    try testing.expectEqual(@as(usize, 5), ac.max_visible);
    try testing.expectEqual(hl, ac.highlight_style);
    try testing.expectEqual(normal, ac.normal_style);
    try testing.expect(ac.show_doc_preview);
    try testing.expectEqual(@as(u16, 50), ac.preview_width);
    try testing.expect(ac.show_metadata_column);
    try testing.expectEqual(@as(u16, 15), ac.metadata_column_width);
    try testing.expectEqual(meta, ac.metadata_style);
    try testing.expectEqual(doc, ac.doc_style);
}

test "autocomplete: render without suggestions leaves the buffer blank" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    var buf = try Buffer.init(testing.allocator, 6, 2);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "      ", "      " });
    for (buf.cells) |cell| try testing.expectEqual(Style{}, cell.style);
}

test "autocomplete: render without suggestions still draws the block" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    _ = ac.setBlock(Block{});
    var buf = try Buffer.init(testing.allocator, 6, 3);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "┌────┐", "│    │", "└────┘" });
}

test "autocomplete: render highlights the selected row across the full width" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "hello", "world" });
    var buf = try Buffer.init(testing.allocator, 20, 4);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "hello               ",
        "world               ",
        "                    ",
        "                    ",
    });
    try expectRowStyle(buf, 0, 0, 20, highlight);
    try expectRowStyle(buf, 1, 0, 20, Style{});
    try expectRowStyle(buf, 2, 0, 20, Style{});
    ac.selectNext();
    ac.render(&buf, fullArea(buf));
    try expectRowStyle(buf, 0, 0, 20, Style{});
    try expectRowStyle(buf, 1, 0, 20, highlight);
}

test "autocomplete: render inside a block fills only the inner area" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    _ = ac.setBlock(Block{});
    try ac.setSuggestions(&.{"hello"});
    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "┌──────────────────┐",
        "│hello             │",
        "│                  │",
        "│                  │",
        "└──────────────────┘",
    });
    try expectRowStyle(buf, 1, 1, 19, highlight);
    try testing.expectEqual(Style{}, buf.getStyle(0, 1));
    try testing.expectEqual(Style{}, buf.getStyle(19, 1));
}

test "autocomplete: render shows at most max_visible rows" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    _ = ac.setMaxVisible(2);
    try ac.setSuggestions(&.{ "a", "b", "c", "d" });
    var buf = try Buffer.init(testing.allocator, 4, 4);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "a   ", "b   ", "    ", "    " });
}

test "autocomplete: render shows the scrolled window with the selection highlighted" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    _ = ac.setMaxVisible(2);
    try ac.setSuggestions(&.{ "a", "b", "c", "d" });
    ac.selectNext();
    ac.selectNext();
    var buf = try Buffer.init(testing.allocator, 4, 3);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "b   ", "c   ", "    " });
    try expectRowStyle(buf, 0, 0, 4, Style{});
    try expectRowStyle(buf, 1, 0, 4, highlight);
}

test "autocomplete: render stops at the area height" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "a", "b", "c" });
    var buf = try Buffer.init(testing.allocator, 4, 3);
    defer buf.deinit();
    ac.render(&buf, .{ .x = 0, .y = 0, .width = 4, .height = 2 });
    try expectRows(buf, &.{ "a   ", "b   ", "    " });
}

test "autocomplete: render cuts text at the area width and respects the area offset" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "abcdefgh", "xy" });
    var buf = try Buffer.init(testing.allocator, 8, 3);
    defer buf.deinit();
    ac.render(&buf, .{ .x = 2, .y = 1, .width = 4, .height = 2 });
    try expectRows(buf, &.{ "        ", "  abcd  ", "  xy    " });
}

test "autocomplete: render draws multibyte text one codepoint per cell" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "héllo", "naïve" });
    var buf = try Buffer.init(testing.allocator, 6, 2);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "héllo ", "naïve " });
}

test "autocomplete: render cuts text by cells and never splits a wide character" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestions(&.{ "日本語", "éééé" });
    var buf = try Buffer.init(testing.allocator, 5, 2);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    // Width 5 holds two double-width characters (4 cells); the fifth cell stays blank.
    try expectRows(buf, &.{ "日 本  ", "éééé " });
}

test "autocomplete: metadata column aligns metadata to the right edge" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "foo", .metadata = "fn" },
        .{ .text = "bar", .metadata = "type" },
        .{ .text = "baz" },
    });
    _ = ac.enableMetadataColumn(true).setMetadataColumnWidth(8);
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "foo         fn      ",
        "bar         type    ",
        "baz                 ",
    });
}

test "autocomplete: metadata column styles follow the selection" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "foo", .metadata = "fn" },
        .{ .text = "bar", .metadata = "type" },
    });
    const meta = Style{ .fg = Color{ .indexed = 3 } };
    _ = ac.enableMetadataColumn(true).setMetadataColumnWidth(8).setMetadataStyle(meta);
    var buf = try Buffer.init(testing.allocator, 20, 2);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    // Row 0 is selected: text uses the highlight style, metadata keeps its colour on the
    // highlight background, and the padding between them is highlighted too.
    const sel_meta = Style{ .fg = meta.fg, .bg = highlight.bg };
    try expectRowStyle(buf, 0, 0, 12, highlight);
    try expectRowStyle(buf, 0, 12, 14, sel_meta);
    try expectRowStyle(buf, 0, 14, 20, highlight);
    try expectRowStyle(buf, 1, 0, 12, Style{});
    try expectRowStyle(buf, 1, 12, 16, meta);
    try expectRowStyle(buf, 1, 16, 20, Style{});
}

test "autocomplete: metadata column clips long text and long metadata" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "foobar", .metadata = "abcdefghijkl" },
        .{ .text = "abcdefghijklmno" },
    });
    _ = ac.enableMetadataColumn(true).setMetadataColumnWidth(8);
    var buf = try Buffer.init(testing.allocator, 12, 2);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    // Text keeps width - meta - 1 = 3 cells; metadata is cut to its 8 cells. An item without
    // metadata uses the whole row.
    try expectRows(buf, &.{ "foo abcdefgh", "abcdefghijkl" });
}

test "autocomplete: metadata column wider than the area still shows the metadata" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{.{ .text = "foo", .metadata = "fn" }});
    _ = ac.enableMetadataColumn(true).setMetadataColumnWidth(20);
    var buf = try Buffer.init(testing.allocator, 6, 1);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{"fn    "});
}

test "autocomplete: metadata is ignored while the column is disabled" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{.{ .text = "foo", .metadata = "fn" }});
    var buf = try Buffer.init(testing.allocator, 8, 1);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{"foo     "});
}

test "autocomplete: doc preview splits the area into list, separator and preview" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{.{ .text = "println", .doc = "Prints a line" }});
    _ = ac.enableDocPreview(true).setPreviewWidth(10);
    var buf = try Buffer.init(testing.allocator, 40, 3);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "println                      │Prints a  ",
        "                             │line      ",
        "                             │          ",
    });
    try expectRowStyle(buf, 0, 0, 29, highlight);
}

test "autocomplete: doc preview follows the selected item" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "alpha", .doc = "first doc" },
        .{ .text = "beta", .doc = "second doc" },
        .{ .text = "gamma" },
    });
    _ = ac.enableDocPreview(true).setPreviewWidth(10);
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "alpha    │first doc ",
        "beta     │          ",
        "gamma    │          ",
    });
    ac.selectNext();
    buf.clear();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "alpha    │second doc",
        "beta     │          ",
        "gamma    │          ",
    });
    ac.selectNext(); // no doc: preview stays blank but the separator remains
    buf.clear();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "alpha    │          ",
        "beta     │          ",
        "gamma    │          ",
    });
}

test "autocomplete: doc preview uses the doc style for text and padding" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{.{ .text = "x", .doc = "hi" }});
    const doc = Style{ .fg = Color{ .indexed = 4 } };
    _ = ac.enableDocPreview(true).setPreviewWidth(6).setDocStyle(doc);
    var buf = try Buffer.init(testing.allocator, 12, 2);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    // list width 12 - 6 - 1 = 5, separator at 5, preview at 6..11.
    try expectRows(buf, &.{ "x    │hi    ", "     │      " });
    try expectRowStyle(buf, 0, 6, 12, doc);
    try expectRowStyle(buf, 1, 6, 12, Style{}); // a one-line doc leaves the second row alone
    try testing.expectEqual(Style{}, buf.getStyle(5, 0));
}

test "autocomplete: doc preview keeps explicit newlines and blank lines" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    // Regression: text after the first newline used to be dropped.
    try ac.setSuggestionsWithDocs(&.{.{ .text = "x", .doc = "ab\n\ncd" }});
    _ = ac.enableDocPreview(true).setPreviewWidth(4);
    var buf = try Buffer.init(testing.allocator, 10, 4);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "x    │ab  ", "     │    ", "     │cd  ", "     │    " });
}

test "autocomplete: doc preview wraps at spaces without repeating words" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    // Regression: the partial word was drawn on both rows.
    try ac.setSuggestionsWithDocs(&.{.{ .text = "x", .doc = "hello world foo" }});
    _ = ac.enableDocPreview(true).setPreviewWidth(8);
    var buf = try Buffer.init(testing.allocator, 20, 4);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "x          │hello   ",
        "           │world   ",
        "           │foo     ",
        "           │        ",
    });
}

test "autocomplete: doc preview breaks cleanly when a word ends exactly at the edge" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{.{ .text = "x", .doc = "abcde fgh" }});
    _ = ac.enableDocPreview(true).setPreviewWidth(5);
    var buf = try Buffer.init(testing.allocator, 12, 3);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "x     │abcde", "      │fgh  ", "      │     " });
}

test "autocomplete: doc preview hard-breaks a word longer than the width" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{.{ .text = "x", .doc = "abcdefghijkl" }});
    _ = ac.enableDocPreview(true).setPreviewWidth(5);
    var buf = try Buffer.init(testing.allocator, 20, 4);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "x             │abcde",
        "              │fghij",
        "              │kl   ",
        "              │     ",
    });
}

test "autocomplete: doc preview wraps wide characters by cells" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{.{ .text = "x", .doc = "日本語日本" }});
    _ = ac.enableDocPreview(true).setPreviewWidth(4);
    var buf = try Buffer.init(testing.allocator, 10, 4);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "x    │日 本 ",
        "     │語 日 ",
        "     │本   ",
        "     │    ",
    });
}

test "autocomplete: doc preview is clipped to the area height" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{.{ .text = "x", .doc = "a\nb\nc\nd" }});
    _ = ac.enableDocPreview(true).setPreviewWidth(2);
    var buf = try Buffer.init(testing.allocator, 8, 4);
    defer buf.deinit();
    ac.render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 2 });
    try expectRows(buf, &.{ "x    │a ", "     │b ", "        ", "        " });
}

test "autocomplete: doc preview that cannot fit leaves the list at full width" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{.{ .text = "x", .doc = "doc" }});
    _ = ac.enableDocPreview(true).setPreviewWidth(30);
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{"x         "});
    // Regression: a preview width near maxInt(u16) used to overflow `preview_width + 2`.
    _ = ac.setPreviewWidth(std.math.maxInt(u16));
    buf.clear();
    ac.render(&buf, fullArea(buf));
    try expectRows(buf, &.{"x         "});
}

test "autocomplete: zero-sized areas write nothing" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{.{ .text = "x", .metadata = "m", .doc = "d" }});
    _ = ac.enableDocPreview(true).setPreviewWidth(1).enableMetadataColumn(true);
    var buf = try Buffer.init(testing.allocator, 8, 2);
    defer buf.deinit();
    ac.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
    ac.render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 0 });
    ac.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 2 });
    try expectRows(buf, &.{ "        ", "        " });
    for (buf.cells) |cell| try testing.expectEqual(Style{}, cell.style);
}

test "autocomplete: areas past the buffer or the u16 range are clipped without overflow" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    try ac.setSuggestionsWithDocs(&.{.{ .text = "item", .metadata = "m", .doc = "doc" }});
    _ = ac.enableDocPreview(true).setPreviewWidth(3).enableMetadataColumn(true);
    var buf = try Buffer.init(testing.allocator, 8, 2);
    defer buf.deinit();
    ac.render(&buf, .{ .x = 65530, .y = 65530, .width = 100, .height = 100 });
    ac.render(&buf, .{ .x = 8, .y = 0, .width = 5, .height = 2 });
    try expectRows(buf, &.{ "        ", "        " });
}

test "autocomplete: block with preview keeps the separator and preview inside the border" {
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    _ = ac.setBlock(Block{});
    try ac.setSuggestionsWithDocs(&.{.{ .text = "ab", .doc = "xy" }});
    _ = ac.enableDocPreview(true).setPreviewWidth(3);
    var buf = try Buffer.init(testing.allocator, 12, 4);
    defer buf.deinit();
    ac.render(&buf, fullArea(buf));
    // inner width 10: list 6, separator, preview 3.
    try expectRows(buf, &.{
        "┌──────────┐",
        "│ab    │xy │",
        "│      │   │",
        "└──────────┘",
    });
}

test "autocomplete: seeded navigation matches a trivial model and renders the selection" {
    var prng = std.Random.DefaultPrng.init(0xA170_C0DE);
    const rng = prng.random();
    const pool = [_][]const u8{
        "alpha", "bravo", "charlie", "delta",  "echo", "foxtrot",
        "golf",  "hotel", "india",   "juliet", "kilo", "lima",
    };
    var ac = Autocomplete.init(testing.allocator);
    defer ac.deinit();
    var buf = try Buffer.init(testing.allocator, 12, 6);
    defer buf.deinit();

    var model_len: usize = 0;
    var model_sel: usize = 0;
    for (0..2000) |_| {
        switch (rng.uintLessThan(u8, 6)) {
            0 => {
                model_len = rng.uintAtMost(usize, pool.len);
                try ac.setSuggestions(pool[0..model_len]);
                model_sel = 0;
            },
            1 => {
                ac.selectNext();
                if (model_sel + 1 < model_len) model_sel += 1;
            },
            2 => {
                ac.selectPrev();
                model_sel -|= 1;
            },
            3 => {
                ac.selectFirst();
                model_sel = 0;
            },
            4 => {
                ac.selectLast();
                if (model_len > 0) model_sel = model_len - 1;
            },
            else => _ = ac.setMaxVisible(rng.uintAtMost(usize, 8)),
        }
        ac.check_invariants();
        try testing.expectEqual(model_len, ac.getSuggestionCount());
        try testing.expectEqual(model_sel, ac.selected_index);
        buf.clear();
        ac.render(&buf, fullArea(buf));
        try expectModelRender(&ac, buf, pool[0..model_len]);
    }
}

/// Check the rendered rows against the model list: row r shows item scroll_offset + r, only the
/// selected item is highlighted, and rows past the visible window stay blank.
fn expectModelRender(ac: *const Autocomplete, buf: Buffer, items: []const []const u8) !void {
    const rows = if (items.len == 0)
        0
    else
        @min(@min(ac.max_visible, items.len - ac.scroll_offset), buf.height);
    var highlighted: usize = 0;
    for (0..buf.height) |y_usize| {
        const y: u16 = @intCast(y_usize);
        if (y >= rows) {
            try expectRowStyle(buf, y, 0, buf.width, Style{});
            try testing.expectEqual(@as(u21, ' '), buf.getChar(0, y));
            continue;
        }
        const idx = ac.scroll_offset + y;
        for (items[idx], 0..) |c, x| {
            try testing.expectEqual(@as(u21, c), buf.getChar(@intCast(x), y));
        }
        try testing.expectEqual(@as(u21, ' '), buf.getChar(@intCast(items[idx].len), y));
        const is_sel = idx == ac.selected_index;
        try testing.expectEqual(if (is_sel) highlight else Style{}, buf.getStyle(0, y));
        if (is_sel) highlighted += 1;
    }
    if (rows > 0 and ac.selected_index - ac.scroll_offset < rows) {
        try testing.expectEqual(@as(usize, 1), highlighted);
    }
}
