//! Unicode Grapheme Cluster Support (UAX#29)
//!
//! This module provides comprehensive support for Unicode grapheme clusters,
//! which are the user-perceived characters that may consist of multiple Unicode
//! codepoints (combining marks, emoji with modifiers, ZWJ sequences, etc).
//!
//! Key features:
//! - UAX#29 grapheme boundary detection
//! - Display width calculation for grapheme clusters
//! - Cursor positioning with grapheme awareness
//! - Text wrapping respecting grapheme boundaries

const std = @import("std");
const Allocator = std.mem.Allocator;
const unicode_mod = @import("unicode.zig");
const UnicodeWidth = unicode_mod.UnicodeWidth;

/// A grapheme cluster representing a user-perceived character.
/// May consist of multiple Unicode codepoints (base + combining marks, emoji + modifiers, etc).
pub const Grapheme = struct {
    bytes: []const u8,
    display_width: u8,

    /// Get the codepoint count in this grapheme
    pub fn codepointCount(self: Grapheme) usize {
        var count: usize = 0;
        var i: usize = 0;
        while (i < self.bytes.len) {
            const byte = self.bytes[i];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;
            if (i + char_len > self.bytes.len) break;
            i += char_len;
            count += 1;
        }
        return count;
    }

    /// Get the first codepoint in this grapheme
    pub fn firstCodepoint(self: Grapheme) u21 {
        if (self.bytes.len == 0) return 0;
        const byte = self.bytes[0];
        const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;
        if (char_len == 1) return @as(u21, byte);
        return std.unicode.utf8Decode(self.bytes[0..@min(char_len, self.bytes.len)]) catch 0;
    }
};

/// Iterator for parsing a UTF-8 string into grapheme clusters
pub const GraphemeIterator = struct {
    text: []const u8,
    pos: usize = 0,

    pub fn init(text: []const u8) GraphemeIterator {
        return .{ .text = text };
    }

    /// Get the next grapheme cluster
    pub fn next(self: *GraphemeIterator) ?Grapheme {
        if (self.pos >= self.text.len) return null;

        const start = self.pos;
        var end = start;

        // Skip BOM if at start
        if (start == 0 and self.text.len >= 3) {
            if (self.text[0] == 0xEF and self.text[1] == 0xBB and self.text[2] == 0xBF) {
                self.pos = 3;
                return self.next();
            }
        }

        // Get first codepoint
        const first_byte = self.text[start];
        const first_len = std.unicode.utf8ByteSequenceLength(first_byte) catch 1;

        if (start + first_len > self.text.len) {
            // Incomplete UTF-8 sequence, skip it
            self.pos = self.text.len;
            const width = getGraphemeWidth(self.text[start..]);
            return Grapheme{ .bytes = self.text[start..], .display_width = width };
        }

        end = start + first_len;
        _ = std.unicode.utf8Decode(self.text[start..end]) catch 0;

        // Extend grapheme cluster according to UAX#29
        while (end < self.text.len) {
            const byte = self.text[end];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (end + char_len > self.text.len) break;

            const next_cp = std.unicode.utf8Decode(self.text[end .. end + char_len]) catch 0;

            if (!shouldContinueGrapheme(self.text[start..end], next_cp)) {
                break;
            }

            end += char_len;
        }

        self.pos = end;
        const slice = self.text[start..end];
        const width = getGraphemeWidth(slice);
        return Grapheme{ .bytes = slice, .display_width = width };
    }

    /// Get the previous grapheme (for backward iteration)
    pub fn prev(self: *GraphemeIterator) ?Grapheme {
        if (self.pos == 0) return null;

        const end = self.pos;
        var start = end;

        // Move back one codepoint
        while (start > 0) {
            start -= 1;
            const byte = self.text[start];
            // Check if this is the start of a UTF-8 sequence
            if ((byte & 0xC0) != 0x80) {
                // This is the start of a codepoint
                break;
            }
        }

        // Now we're at a codepoint boundary, but need to extend backward to include all combining marks
        if (start > 0) {
            var temp_start = start;

            // Look back from temp_start to see if we're a combining mark
            while (temp_start > 0) {
                var prev_start = temp_start - 1;
                while (prev_start > 0 and (self.text[prev_start] & 0xC0) == 0x80) {
                    prev_start -= 1;
                }

                const prev_byte = self.text[prev_start];
                const prev_len = std.unicode.utf8ByteSequenceLength(prev_byte) catch 1;
                if (prev_start + prev_len > temp_start) break;

                const prev_cp = std.unicode.utf8Decode(self.text[prev_start .. prev_start + prev_len]) catch 0;

                // If we're a combining mark, keep going back
                if (isCombiningMark(prev_cp) || isZWJ(prev_cp) || isSkinTone(prev_cp) || isVariationSelector(prev_cp) || isEnclosingMark(prev_cp)) {
                    temp_start = prev_start;
                } else {
                    break;
                }
            }

            start = temp_start;
        }

        self.pos = start;
        const slice = self.text[start..end];
        const width = getGraphemeWidth(slice);
        return Grapheme{ .bytes = slice, .display_width = width };
    }
};

/// Calculate the display width of a grapheme cluster (0, 1, or 2 cells)
pub fn graphemeWidth(grapheme: Grapheme) u8 {
    return grapheme.display_width;
}

/// Calculate total display width of a UTF-8 string in terminal cells,
/// respecting grapheme cluster boundaries
pub fn stringWidth(text: []const u8) usize {
    var total: usize = 0;
    var iter = GraphemeIterator.init(text);
    while (iter.next()) |grapheme| {
        total += grapheme.display_width;
    }
    return total;
}

/// Move cursor to the next grapheme cluster
pub fn nextGraphemePos(text: []const u8, pos: usize) usize {
    if (pos >= text.len) return text.len;

    var iter = GraphemeIterator.init(text);
    var current_pos: usize = 0;

    while (iter.next()) |grapheme| {
        const next_pos = current_pos + grapheme.bytes.len;
        if (next_pos > pos) {
            return next_pos;
        }
        current_pos = next_pos;
    }

    return text.len;
}

/// Move cursor to the previous grapheme cluster
pub fn prevGraphemePos(text: []const u8, pos: usize) usize {
    if (pos == 0) return 0;

    // Make sure pos doesn't exceed text length
    const safe_pos = @min(pos, text.len);

    var iter = GraphemeIterator.init(text[0..safe_pos]);
    var prev_pos: usize = 0;
    var current_pos: usize = 0;

    while (iter.next()) |grapheme| {
        prev_pos = current_pos;
        current_pos += grapheme.bytes.len;
    }

    // If we consumed the entire range, return the start of the last grapheme
    // Otherwise return the current position (shouldn't happen)
    return prev_pos;
}

/// Wrap text to fit within max_width terminal cells,
/// respecting grapheme cluster boundaries
pub fn wrapText(allocator: Allocator, text: []const u8, max_width: usize) ![][]const u8 {
    var lines = std.ArrayList([]const u8).init(allocator);
    defer lines.deinit();

    var current_line_start: usize = 0;
    var current_width: usize = 0;
    var last_break: usize = 0;

    var iter = GraphemeIterator.init(text);
    var pos: usize = 0;

    while (iter.next()) |grapheme| {
        const next_pos = pos + grapheme.bytes.len;
        const grapheme_w = grapheme.display_width;

        if (current_width + grapheme_w > max_width) {
            // Line is full
            if (last_break > current_line_start) {
                try lines.append(text[current_line_start..last_break]);
                current_line_start = last_break;
                current_width = 0;
                last_break = current_line_start;
                pos = current_line_start;
                iter.pos = pos;
            } else {
                // Force break at this grapheme
                try lines.append(text[current_line_start..pos]);
                current_line_start = pos;
                current_width = grapheme_w;
                last_break = current_line_start;
            }
        } else {
            current_width += grapheme_w;
            if (grapheme.bytes[0] == ' ') {
                last_break = next_pos;
            }
            pos = next_pos;
        }
    }

    // Add remaining text
    if (current_line_start < text.len) {
        try lines.append(text[current_line_start..]);
    }

    return lines.toOwnedSlice();
}

/// Check if a grapheme cluster at the given byte position should continue
/// to include the next codepoint (used internally by GraphemeIterator)
fn shouldContinueGrapheme(grapheme_so_far: []const u8, next_cp: u21) bool {
    // Get the last codepoint in the grapheme so far
    var last_cp: u21 = 0;
    var i: usize = 0;
    while (i < grapheme_so_far.len) {
        const byte = grapheme_so_far[i];
        const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;
        if (i + char_len > grapheme_so_far.len) break;
        last_cp = std.unicode.utf8Decode(grapheme_so_far[i .. i + char_len]) catch 0;
        i += char_len;
    }

    // UAX#29 Grapheme Cluster Boundary Rules

    // Combining marks attach to base character
    if (isCombiningMark(next_cp)) return true;

    // Zero-Width Joiner sequences (emoji families)
    if (isZWJ(next_cp) or (last_cp == 0x200D and next_cp >= 0x1F000)) {
        return true;
    }

    // Emoji modifiers (skin tones, etc)
    if (isSkinTone(next_cp) and isEmojiBase(last_cp)) {
        return true;
    }

    // Variation selectors
    if (isVariationSelector(next_cp)) return true;

    // Enclosing marks
    if (isEnclosingMark(next_cp)) return true;

    // Regional indicator pairs (flags like 🇺🇸)
    if (isRegionalIndicator(last_cp) and isRegionalIndicator(next_cp)) {
        // Check if this is a valid pair
        return true;
    }

    // Hangul jamo composition
    if (isHangulBase(last_cp) and isHangulJamo(next_cp)) {
        return true;
    }

    return false;
}

/// Get the display width of a grapheme cluster
fn getGraphemeWidth(grapheme: []const u8) u8 {
    if (grapheme.len == 0) return 0;

    var width: u8 = 0;
    var first = true;
    var i: usize = 0;

    while (i < grapheme.len) {
        const byte = grapheme[i];
        const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;
        if (i + char_len > grapheme.len) break;

        const cp = std.unicode.utf8Decode(grapheme[i .. i + char_len]) catch 0;

        if (first) {
            width = UnicodeWidth.charWidth(cp);
            first = false;
        } else {
            // Combining marks and modifiers don't add width
            if (!isCombiningMark(cp) and !isSkinTone(cp) and !isVariationSelector(cp) and !isZWJ(cp) and !isEnclosingMark(cp)) {
                // This shouldn't happen in a well-formed grapheme, but be safe
                width = 0;
            }
        }

        i += char_len;
    }

    return width;
}

/// Check if a codepoint is a combining mark (diacritical mark)
fn isCombiningMark(cp: u21) bool {
    // Combining Diacritical Marks (U+0300-U+036F)
    if (cp >= 0x0300 and cp <= 0x036F) return true;

    // Combining Diacritical Marks Extended (U+1AB0-U+1AFF)
    if (cp >= 0x1AB0 and cp <= 0x1AFF) return true;

    // Combining Diacritical Marks Supplement (U+1DC0-U+1DFF)
    if (cp >= 0x1DC0 and cp <= 0x1DFF) return true;

    // Other combining marks in various blocks
    // Combining Half Marks (U+FE20-U+FE2F)
    if (cp >= 0xFE20 and cp <= 0xFE2F) return true;

    return false;
}

/// Check if a codepoint is a zero-width joiner (ZWJ)
fn isZWJ(cp: u21) bool {
    return cp == 0x200D; // Zero Width Joiner
}

/// Check if a codepoint is a skin tone modifier
fn isSkinTone(cp: u21) bool {
    // Emoji Modifier Fitzpatrick Type-1-2 through Type-6
    return (cp >= 0x1F3FB and cp <= 0x1F3FF);
}

/// Check if a codepoint is a variation selector
fn isVariationSelector(cp: u21) bool {
    // Variation Selectors (U+FE00-U+FE0F)
    if (cp >= 0xFE00 and cp <= 0xFE0F) return true;

    // Variation Selectors Supplement (U+E0100-U+E01EF)
    if (cp >= 0xE0100 and cp <= 0xE01EF) return true;

    return false;
}

/// Check if a codepoint is an enclosing mark
fn isEnclosingMark(cp: u21) bool {
    // Enclosing marks can appear after any character
    // U+20DD (Combining Enclosing Circle) and similar
    if (cp == 0x20DD) return true; // Combining Enclosing Circle
    if (cp == 0x20DE) return true; // Combining Enclosing Square
    if (cp == 0x20DF) return true; // Combining Enclosing Diamond
    if (cp == 0x20E0) return true; // Combining Enclosing Circle Backslash
    if (cp == 0x20E2) return true; // Combining Enclosing Screen
    if (cp == 0x20E3) return true; // Combining Enclosing Keycap
    if (cp == 0x20E4) return true; // Combining Enclosing Upward Pointing Triangle
    return false;
}

/// Check if a codepoint is an emoji base that can take modifiers
fn isEmojiBase(cp: u21) bool {
    // Simplified check: most emoji in the expected ranges
    if (cp >= 0x1F000 and cp <= 0x1F9FF) return true;
    if (cp >= 0x1F600 and cp <= 0x1F64F) return true; // Emoticons
    if (cp == 0x2764) return true; // Heavy Black Heart
    return false;
}

/// Check if a codepoint is a regional indicator (for flags)
fn isRegionalIndicator(cp: u21) bool {
    // Regional Indicator Symbols (U+1F1E6-U+1F1FF)
    return (cp >= 0x1F1E6 and cp <= 0x1F1FF);
}

/// Check if a codepoint is a Hangul base character
fn isHangulBase(cp: u21) bool {
    // Hangul Syllables (U+AC00-U+D7A3)
    return (cp >= 0xAC00 and cp <= 0xD7A3);
}

/// Check if a codepoint is a Hangul jamo (initial/medial/final)
fn isHangulJamo(cp: u21) bool {
    // Hangul Jamo (U+1100-U+11FF)
    if (cp >= 0x1100 and cp <= 0x11FF) return true;

    // Hangul Compatibility Jamo (U+3130-U+318F)
    if (cp >= 0x3130 and cp <= 0x318F) return true;

    return false;
}

// Tests

test "grapheme boundary: single ASCII character" {
    const text = "A";
    var iter = GraphemeIterator.init(text);
    const g = iter.next();
    try std.testing.expect(g != null);
    if (g) |grapheme| {
        try std.testing.expectEqualStrings("A", grapheme.bytes);
        try std.testing.expectEqual(@as(u8, 1), grapheme.display_width);
    }
}

test "grapheme boundary: ASCII word" {
    const text = "Hello";
    var iter = GraphemeIterator.init(text);
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), count);
}

test "grapheme boundary: combining mark (diacritic)" {
    const decomposed = "e\u{0301}"; // e + combining acute
    var iter = GraphemeIterator.init(decomposed);
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "grapheme boundary: multiple combining marks" {
    const text = "n\u{0300}\u{0304}"; // n + grave + macron
    var iter = GraphemeIterator.init(text);
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "grapheme boundary: emoji with skin tone modifier" {
    const text = "👋🏽";
    var iter = GraphemeIterator.init(text);
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "grapheme boundary: ZWJ sequence (emoji family)" {
    const text = "👨‍👩‍👧‍👦";
    var iter = GraphemeIterator.init(text);
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "grapheme boundary: regional indicator pair (flag)" {
    const text = "🇺🇸";
    var iter = GraphemeIterator.init(text);
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "grapheme width: ASCII character (1 cell)" {
    const text = "A";
    var iter = GraphemeIterator.init(text);
    if (iter.next()) |grapheme| {
        try std.testing.expectEqual(@as(u8, 1), grapheme.display_width);
    }
}

test "grapheme width: emoji base (2 cells)" {
    const text = "👋";
    var iter = GraphemeIterator.init(text);
    if (iter.next()) |grapheme| {
        try std.testing.expectEqual(@as(u8, 2), grapheme.display_width);
    }
}

test "grapheme width: emoji with skin tone modifier (2 cells)" {
    const text = "👋🏽";
    var iter = GraphemeIterator.init(text);
    if (iter.next()) |grapheme| {
        try std.testing.expectEqual(@as(u8, 2), grapheme.display_width);
    }
}

test "grapheme width: combining mark (0 cells)" {
    const text = "e\u{0301}";
    var iter = GraphemeIterator.init(text);
    if (iter.next()) |grapheme| {
        try std.testing.expectEqual(@as(u8, 1), grapheme.display_width);
    }
}

test "grapheme width: CJK character (2 cells)" {
    const text = "中";
    var iter = GraphemeIterator.init(text);
    if (iter.next()) |grapheme| {
        try std.testing.expectEqual(@as(u8, 2), grapheme.display_width);
    }
}

test "cursor position: next grapheme after ASCII" {
    const text = "ABC";
    const next_pos = nextGraphemePos(text, 0);
    try std.testing.expectEqual(@as(usize, 1), next_pos);
}

test "cursor position: next grapheme with combining mark" {
    const text = "e\u{0301}X";
    const next_pos = nextGraphemePos(text, 0);
    // Should skip both 'e' and combining mark (3 bytes total for e+combining)
    try std.testing.expectEqual(@as(usize, 3), next_pos);
}

test "cursor position: prev grapheme from emoji" {
    const text = "Hi 👋";
    const prev_pos = prevGraphemePos(text, text.len);
    try std.testing.expect(prev_pos < text.len);
    try std.testing.expect(prev_pos > 0);
}
