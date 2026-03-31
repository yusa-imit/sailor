const std = @import("std");

/// Unicode character width calculation for terminal rendering.
/// Handles East Asian Width property (UAX #11) and emoji display width.
pub const UnicodeWidth = struct {
    /// Calculate display width of a Unicode codepoint in terminal cells.
    /// Returns 0, 1, or 2 based on character properties.
    ///
    /// Rules:
    /// - Control characters (0x00-0x1F, 0x7F-0x9F): width 0
    /// - Combining marks (U+0300-U+036F, etc.): width 0
    /// - Zero-width characters (ZWSP, ZWNJ, etc.): width 0
    /// - CJK Unified Ideographs: width 2
    /// - Hangul Syllables: width 2
    /// - Emoji (U+1F300-U+1F9FF): width 2
    /// - East Asian Wide/Fullwidth: width 2
    /// - Most other characters: width 1
    pub fn charWidth(codepoint: u21) u8 {
        // Control characters and DEL
        if (codepoint < 0x20 or (codepoint >= 0x7F and codepoint < 0xA0)) {
            return 0;
        }

        // Combining diacritical marks (U+0300-U+036F)
        if (codepoint >= 0x0300 and codepoint <= 0x036F) {
            return 0;
        }

        // Zero-width characters
        if (isZeroWidth(codepoint)) {
            return 0;
        }

        // East Asian Wide and Fullwidth characters
        if (isWide(codepoint)) {
            return 2;
        }

        // Default: narrow character
        return 1;
    }

    /// Calculate total display width of a UTF-8 string in terminal cells.
    /// Sums character widths for all codepoints in the string.
    /// Handles CJK (2 cells), emoji (2 cells), combining marks (0 cells).
    /// Returns total number of terminal columns needed to display the string.
    pub fn stringWidth(str: []const u8) usize {
        var total: usize = 0;
        var i: usize = 0;

        while (i < str.len) {
            const byte = str[i];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (i + char_len > str.len) break;

            const codepoint = if (char_len == 1)
                @as(u21, byte)
            else
                std.unicode.utf8Decode(str[i .. i + char_len]) catch @as(u21, byte);

            total += charWidth(codepoint);
            i += char_len;
        }

        return total;
    }

    /// Truncate string to fit within max_width terminal cells.
    /// Returns the byte index where truncation should occur.
    /// Ensures wide characters (CJK, emoji) are not split mid-character.
    /// Use this for text fitting in fixed-width terminal areas.
    /// Example: truncate("Hello 你好", 7) → byte index of end of "Hello 你" (9)
    pub fn truncate(str: []const u8, max_width: usize) usize {
        var width: usize = 0;
        var i: usize = 0;

        while (i < str.len) {
            const byte = str[i];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (i + char_len > str.len) break;

            const codepoint = if (char_len == 1)
                @as(u21, byte)
            else
                std.unicode.utf8Decode(str[i .. i + char_len]) catch @as(u21, byte);

            const char_w = charWidth(codepoint);
            if (width + char_w > max_width) break;

            width += char_w;
            i += char_len;
        }

        return i;
    }

    /// Check if codepoint is zero-width.
    fn isZeroWidth(cp: u21) bool {
        // Zero Width Space (U+200B)
        if (cp == 0x200B) return true;
        // Zero Width Non-Joiner (U+200C)
        if (cp == 0x200C) return true;
        // Zero Width Joiner (U+200D)
        if (cp == 0x200D) return true;
        // Word Joiner (U+2060)
        if (cp == 0x2060) return true;
        // Zero Width No-Break Space (U+FEFF)
        if (cp == 0xFEFF) return true;

        // Variation Selectors (U+FE00-U+FE0F)
        if (cp >= 0xFE00 and cp <= 0xFE0F) return true;

        // Combining marks in other ranges
        if (cp >= 0x0483 and cp <= 0x0489) return true; // Cyrillic combining
        if (cp >= 0x0591 and cp <= 0x05BD) return true; // Hebrew combining
        if (cp >= 0x0610 and cp <= 0x061A) return true; // Arabic combining

        return false;
    }

    /// Check if codepoint has East Asian Wide property (2 cells).
    fn isWide(cp: u21) bool {
        // CJK Unified Ideographs (U+4E00-U+9FFF)
        if (cp >= 0x4E00 and cp <= 0x9FFF) return true;

        // CJK Compatibility Ideographs (U+F900-U+FAFF)
        if (cp >= 0xF900 and cp <= 0xFAFF) return true;

        // CJK Unified Ideographs Extension A (U+3400-U+4DBF)
        if (cp >= 0x3400 and cp <= 0x4DBF) return true;

        // Hangul Syllables (U+AC00-U+D7A3)
        if (cp >= 0xAC00 and cp <= 0xD7A3) return true;

        // Hangul Jamo (U+1100-U+11FF)
        if (cp >= 0x1100 and cp <= 0x11FF) return true;

        // Hiragana (U+3040-U+309F)
        if (cp >= 0x3040 and cp <= 0x309F) return true;

        // Katakana (U+30A0-U+30FF)
        if (cp >= 0x30A0 and cp <= 0x30FF) return true;

        // Halfwidth and Fullwidth Forms (U+FF00-U+FFEF) - only fullwidth
        if (cp >= 0xFF01 and cp <= 0xFF60) return true;

        // Emoji ranges (simplified - covers most common emoji)
        // Emoticons (U+1F600-U+1F64F)
        if (cp >= 0x1F600 and cp <= 0x1F64F) return true;

        // Miscellaneous Symbols and Pictographs (U+1F300-U+1F5FF)
        if (cp >= 0x1F300 and cp <= 0x1F5FF) return true;

        // Transport and Map Symbols (U+1F680-U+1F6FF)
        if (cp >= 0x1F680 and cp <= 0x1F6FF) return true;

        // Supplemental Symbols and Pictographs (U+1F900-U+1F9FF)
        if (cp >= 0x1F900 and cp <= 0x1F9FF) return true;

        // Symbols and Pictographs Extended-A (U+1FA70-U+1FAFF)
        if (cp >= 0x1FA70 and cp <= 0x1FAFF) return true;

        // Some other common wide characters
        if (cp >= 0x2E80 and cp <= 0x2EFF) return true; // CJK Radicals
        if (cp >= 0x3000 and cp <= 0x303F) return true; // CJK Symbols and Punctuation
        if (cp >= 0x31C0 and cp <= 0x31EF) return true; // CJK Strokes

        return false;
    }
};

// Tests
test "UnicodeWidth.charWidth - ASCII" {
    try std.testing.expectEqual(@as(u8, 1), UnicodeWidth.charWidth('A'));
    try std.testing.expectEqual(@as(u8, 1), UnicodeWidth.charWidth('z'));
    try std.testing.expectEqual(@as(u8, 1), UnicodeWidth.charWidth('0'));
    try std.testing.expectEqual(@as(u8, 1), UnicodeWidth.charWidth(' '));
}

test "UnicodeWidth.charWidth - control characters" {
    try std.testing.expectEqual(@as(u8, 0), UnicodeWidth.charWidth('\x00'));
    try std.testing.expectEqual(@as(u8, 0), UnicodeWidth.charWidth('\n'));
    try std.testing.expectEqual(@as(u8, 0), UnicodeWidth.charWidth('\t'));
    try std.testing.expectEqual(@as(u8, 0), UnicodeWidth.charWidth(0x7F)); // DEL
}

test "UnicodeWidth.charWidth - CJK characters" {
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('你')); // U+4F60
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('好')); // U+597D
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('世')); // U+4E16
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('界')); // U+754C
}

test "UnicodeWidth.charWidth - Hangul" {
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('안')); // U+C548
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('녕')); // U+B155
}

test "UnicodeWidth.charWidth - Japanese Hiragana" {
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('あ')); // U+3042
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('い')); // U+3044
}

test "UnicodeWidth.charWidth - Japanese Katakana" {
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('ア')); // U+30A2
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('イ')); // U+30A4
}

test "UnicodeWidth.charWidth - emoji" {
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('😀')); // U+1F600
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('👋')); // U+1F44B
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('🚀')); // U+1F680
    try std.testing.expectEqual(@as(u8, 2), UnicodeWidth.charWidth('🎉')); // U+1F389
}

test "UnicodeWidth.charWidth - combining marks" {
    try std.testing.expectEqual(@as(u8, 0), UnicodeWidth.charWidth(0x0301)); // Combining acute
    try std.testing.expectEqual(@as(u8, 0), UnicodeWidth.charWidth(0x0300)); // Combining grave
}

test "UnicodeWidth.charWidth - zero-width characters" {
    try std.testing.expectEqual(@as(u8, 0), UnicodeWidth.charWidth(0x200B)); // ZWSP
    try std.testing.expectEqual(@as(u8, 0), UnicodeWidth.charWidth(0x200C)); // ZWNJ
    try std.testing.expectEqual(@as(u8, 0), UnicodeWidth.charWidth(0x200D)); // ZWJ
}

test "UnicodeWidth.stringWidth - ASCII" {
    try std.testing.expectEqual(@as(usize, 5), UnicodeWidth.stringWidth("Hello"));
    try std.testing.expectEqual(@as(usize, 13), UnicodeWidth.stringWidth("Hello, World!"));
}

test "UnicodeWidth.stringWidth - mixed content" {
    // "Hello 你好" = "Hello " (6 cells) + "你好" (2 chars × 2 cells) = 10 cells
    try std.testing.expectEqual(@as(usize, 10), UnicodeWidth.stringWidth("Hello 你好"));

    // "Hi 👋" = "Hi " (3 cells) + "👋" (1 char × 2 cells) = 5 cells
    try std.testing.expectEqual(@as(usize, 5), UnicodeWidth.stringWidth("Hi 👋"));
}

test "UnicodeWidth.stringWidth - pure CJK" {
    // 你好世界 = 4 chars × 2 cells = 8
    try std.testing.expectEqual(@as(usize, 8), UnicodeWidth.stringWidth("你好世界"));
}

test "UnicodeWidth.stringWidth - pure emoji" {
    // 😀😃😄 = 3 emoji × 2 cells = 6
    try std.testing.expectEqual(@as(usize, 6), UnicodeWidth.stringWidth("😀😃😄"));
}

test "UnicodeWidth.truncate - ASCII" {
    const str = "Hello, World!";
    try std.testing.expectEqual(@as(usize, 5), UnicodeWidth.truncate(str, 5));
    try std.testing.expectEqual(@as(usize, 7), UnicodeWidth.truncate(str, 7));
    try std.testing.expectEqual(@as(usize, 13), UnicodeWidth.truncate(str, 20));
}

test "UnicodeWidth.truncate - CJK" {
    const str = "你好世界";
    // 你好 = 4 cells, can't fit 世 (would be 6 cells)
    try std.testing.expectEqual(@as(usize, 6), UnicodeWidth.truncate(str, 4));
    // 你好世 = 6 cells
    try std.testing.expectEqual(@as(usize, 9), UnicodeWidth.truncate(str, 6));
}

test "UnicodeWidth.truncate - mixed" {
    const str = "Hi 你好";
    // "Hi " = 3 cells, can't fit 你 (would be 5 cells)
    try std.testing.expectEqual(@as(usize, 3), UnicodeWidth.truncate(str, 3));
    // "Hi 你" = 5 cells
    try std.testing.expectEqual(@as(usize, 6), UnicodeWidth.truncate(str, 5));
}

test "UnicodeWidth.truncate - emoji" {
    const str = "Hi 👋🌍";
    // "Hi " = 3 cells, can't fit 👋 (would be 5 cells)
    try std.testing.expectEqual(@as(usize, 3), UnicodeWidth.truncate(str, 3));
    // "Hi 👋" = 5 cells
    const hi_wave_len = 3 + "👋".len;
    try std.testing.expectEqual(@as(usize, hi_wave_len), UnicodeWidth.truncate(str, 5));
}

test "UnicodeWidth.truncate - zero width" {
    const str = "a\u{0301}b"; // a + combining acute + b
    // a = 1 cell, combining acute = 0 cells, so can fit both in 1 cell
    try std.testing.expectEqual(@as(usize, 3), UnicodeWidth.truncate(str, 1));
}
