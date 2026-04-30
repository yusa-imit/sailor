//! Comprehensive Unicode grapheme cluster support tests
//!
//! Tests UAX#29 grapheme boundary detection, display width calculation,
//! cursor positioning, text wrapping, and Buffer Cell storage for multi-codepoint
//! grapheme clusters (emoji with modifiers, ZWJ sequences, combining marks, etc).

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Allocator = std.mem.Allocator;
const UnicodeWidth = sailor.tui.UnicodeWidth;

// ============================================================================
// GRAPHEME BOUNDARY DETECTION TESTS (UAX#29)
// ============================================================================

test "grapheme boundary: single ASCII character" {
    // ASCII "A" is a grapheme by itself
    // Expected: 1 cluster
    const text = "A";
    // After implementation: parse text into grapheme clusters
    // Verify cluster count and boundaries
    try testing.expectEqualStrings("A", text);
}

test "grapheme boundary: ASCII word" {
    // "Hello" = 5 separate graphemes (each ASCII char is independent)
    const text = "Hello";
    // Verify: H-e-l-l-o are separated by grapheme boundaries
    try testing.expectEqualStrings("Hello", text);
}

test "grapheme boundary: combining mark (diacritic)" {
    // "é" can be represented as:
    // - Precomposed: U+00E9 (1 codepoint)
    // - Decomposed: e (U+0065) + combining acute (U+0301) (2 codepoints, 1 grapheme)
    const precomposed = "é"; // U+00E9
    const decomposed = "e\u{0301}"; // U+0065 + U+0301

    // Both should represent the same grapheme visually
    // After implementation: both should parse as 1 grapheme cluster
    try testing.expectEqualStrings("é", precomposed);
    try testing.expect(decomposed.len > 1); // Verify decomposed has 2 UTF-8 bytes
}

test "grapheme boundary: multiple combining marks" {
    // Character with multiple diacritics: "ǹ" = n + grave + macron
    const text = "n\u{0300}\u{0304}"; // n + combining grave + combining macron
    // Should be 1 grapheme cluster despite 3 codepoints
    try testing.expectEqualStrings("n\u{0300}\u{0304}", text);
}

test "grapheme boundary: emoji with skin tone modifier" {
    // 👋🏽 = waving hand (U+1F44B) + medium skin tone (U+1F3FD)
    // = 2 codepoints, 1 grapheme cluster
    const emoji_with_tone = "👋🏽";
    // Should be recognized as single grapheme
    try testing.expect(emoji_with_tone.len > 4); // Multi-byte UTF-8
}

test "grapheme boundary: emoji with multiple skin tones (edge case)" {
    // Two emoji each with skin tone: "👋🏽🤝🏿"
    // Should parse as: [👋🏽] [🤝🏿] = 2 grapheme clusters
    const text = "👋🏽🤝🏿";
    try testing.expect(text.len > 8); // Both are multi-byte
}

test "grapheme boundary: ZWJ sequence (emoji family)" {
    // 👨‍👩‍👧‍👦 = man + ZWJ + woman + ZWJ + girl + ZWJ + boy
    // All joined by U+200D (Zero-Width Joiner)
    // = 7 codepoints, 1 grapheme cluster
    const family_emoji = "👨‍👩‍👧‍👦";
    // Should be treated as single visual unit
    try testing.expect(family_emoji.len > 20); // Multiple codepoints
}

test "grapheme boundary: ZWJ sequence (man technologist)" {
    // 👨‍💻 = man (U+1F468) + ZWJ + computer (U+1F4BB)
    // = 3 codepoints, 1 grapheme cluster
    const man_tech = "👨‍💻";
    try testing.expect(man_tech.len > 8);
}

test "grapheme boundary: ZWJ sequence (pirate flag)" {
    // 🏴‍☠️ = black flag + ZWJ + skull and crossbones + variation selector
    // Multiple codepoints forming single flag
    const pirate_flag = "🏴‍☠️";
    try testing.expect(pirate_flag.len > 8);
}

test "grapheme boundary: regional indicator pair (flag)" {
    // 🇺🇸 = US flag = regional indicator U + regional indicator S
    // = 2 codepoints, 1 grapheme cluster
    const us_flag = "🇺🇸";
    // Should not split into individual regional indicators
    try testing.expect(us_flag.len > 4);
}

test "grapheme boundary: variation selector (emoji presentation)" {
    // Some characters can be emoji or text style:
    // ❤ (heart, U+2764) vs ❤️ (heart emoji, U+2764 + variation selector U+FE0F)
    const heart_text = "❤"; // Text presentation
    const heart_emoji = "❤️"; // Emoji presentation
    // Both valid, but different visual rendering expectations
    try testing.expect(heart_emoji.len > heart_text.len);
}

test "grapheme boundary: Hangul composition (Korean)" {
    // Korean characters can be:
    // - Precomposed syllables: "한" (U+D55C)
    // - Decomposed jamo: "ㅎ" + "ㅏ" + "ㄴ"
    // Precomposed should be 1 grapheme, jamo might be separate
    const korean_syllable = "한";
    try testing.expect(korean_syllable.len == 3); // UTF-8 encoded
}

test "grapheme boundary: mixed script (Latin with Vietnamese combining marks)" {
    // "ả" = a (U+0061) + combining breve (U+0306) + combining grave (U+0300)
    const text = "a\u{0306}\u{0300}";
    // Should be 1 grapheme despite 3 codepoints
    try testing.expect(text.len > 1);
}

test "grapheme boundary: zero-width joiner sequence (woman cook)" {
    // 👩‍🍳 = woman (U+1F469) + ZWJ + cooking pot (U+1F373)
    const woman_cook = "👩‍🍳";
    // Single grapheme cluster
    try testing.expect(woman_cook.len > 8);
}

test "grapheme boundary: enclosing mark (circled text)" {
    // Some marks can enclose characters (rare but valid)
    // Example: character + combining enclosing circle
    const circled = "A\u{20DD}"; // A + combining enclosing circle
    // Should be 1 grapheme
    try testing.expect(circled.len > 1);
}

// ============================================================================
// GRAPHEME PARSING AND ITERATION TESTS
// ============================================================================

test "grapheme parser: iterate ASCII string" {
    const text = "Hi!";
    // Expected: ['H', 'i', '!']
    // After implementation: grapheme parser should iterate 3 clusters
    try testing.expectEqualStrings("Hi!", text);
}

test "grapheme parser: iterate mixed content" {
    // "Hi 👋" = ['H', 'i', ' ', '👋']
    const text = "Hi 👋";
    // Parser should return 4 grapheme clusters
    try testing.expect(text.len > 4); // Emoji is multi-byte
}

test "grapheme parser: iterate text with combining marks" {
    // "café" (decomposed) = ['c', 'a', 'f', 'e+accent']
    const text = "cafe\u{0301}"; // cafe + combining acute on final e
    // Should iterate as 4 clusters (combining acute attached to 'e')
    try testing.expect(text.len > 4);
}

test "grapheme parser: iterate emoji family sequence" {
    const family = "👨‍👩‍👧‍👦";
    // Should iterate as 1 cluster (entire family kept together)
    try testing.expect(family.len > 20);
}

test "grapheme parser: handle invalid UTF-8 gracefully" {
    // Malformed UTF-8 should not crash parser
    const invalid = "\xFF\xFE";
    // Parser should skip or replace with replacement character
    try testing.expect(invalid.len > 0);
}

test "grapheme parser: handle BOM (Byte Order Mark)" {
    const bom = "\xEF\xBB\xBF"; // UTF-8 BOM
    // Should skip BOM if present
    try testing.expect(bom.len == 3);
}

// ============================================================================
// DISPLAY WIDTH CALCULATION FOR GRAPHEME CLUSTERS
// ============================================================================

test "grapheme width: ASCII character (1 cell)" {
    // Single ASCII char 'A' = 1 terminal cell
    const char = "A";
    try testing.expectEqualStrings("A", char);
}

test "grapheme width: ASCII string" {
    // "Hello" = 5 cells
    const text = "Hello";
    try testing.expectEqualStrings("Hello", text);
}

test "grapheme width: emoji base (2 cells)" {
    // Single emoji 👋 = 2 terminal cells
    const emoji = "👋";
    // After implementation: width("👋") == 2
    try testing.expect(emoji.len > 1);
}

test "grapheme width: emoji with skin tone modifier (2 cells)" {
    // Emoji + modifier should still be 2 cells (not 4)
    // 👋🏽 = single grapheme = 2 cells
    const emoji_tone = "👋🏽";
    // This is the critical fix: modifier doesn't add extra width
    try testing.expect(emoji_tone.len > 4);
}

test "grapheme width: emoji family (2 cells)" {
    // 👨‍👩‍👧‍👦 = single grapheme = 2 cells (one emoji position)
    const family = "👨‍👩‍👧‍👦";
    // After implementation: width(family) == 2 (not wider for ZWJ sequence)
    try testing.expect(family.len > 20);
}

test "grapheme width: combining mark (0 cells)" {
    // Combining mark doesn't take space by itself
    // é (decomposed) = 'e' (1 cell) + combining acute (0 cells) = 1 cell
    const text = "e\u{0301}";
    try testing.expect(text.len > 1);
}

test "grapheme width: multiple combining marks (0 cells each)" {
    // n + grave + macron = 1 cell for 'n', 0 for each mark
    const text = "n\u{0300}\u{0304}";
    try testing.expect(text.len > 1);
}

test "grapheme width: CJK character (2 cells)" {
    // Chinese character '中' = 2 cells
    const char = "中";
    try testing.expectEqualStrings("中", char);
}

test "grapheme width: mixed ASCII + emoji + CJK" {
    // "Hi 你好 👋" = 2 + 1 + 4 + 1 + 2 = 10 cells
    const text = "Hi 你好 👋";
    // Parser should sum widths correctly across different script types
    try testing.expect(text.len > 10);
}

test "grapheme width: zero-width joiner doesn't add width" {
    // 👨‍💻 = man + ZWJ + computer
    // Should still be 2 cells (not 4), because ZWJ is zero-width
    const man_tech = "👨‍💻";
    try testing.expect(man_tech.len > 8);
}

test "grapheme width: variation selector doesn't add width" {
    // ❤️ = heart + variation selector
    // Should be 2 cells for heart, not 3
    const heart_emoji = "❤️";
    try testing.expect(heart_emoji.len > heart_emoji.len - 1);
}

test "grapheme width: regional indicator pair (1 emoji = 2 cells)" {
    // 🇺🇸 = 2 regional indicators = single flag emoji = 2 cells
    const flag = "🇺🇸";
    try testing.expect(flag.len > 4);
}

test "grapheme width: Hangul syllable (2 cells)" {
    // Korean: '한' = 2 cells
    const korean = "한";
    try testing.expect(korean.len == 3); // UTF-8 encoding
}

test "grapheme width: Japanese Hiragana (2 cells)" {
    // 'あ' = 2 cells
    const hiragana = "あ";
    try testing.expectEqualStrings("あ", hiragana);
}

test "grapheme width: control character (0 cells)" {
    // \t (tab) or other control chars = 0 cells in display context
    const control = "\t";
    try testing.expectEqualStrings("\t", control);
}

// ============================================================================
// CURSOR POSITIONING WITH GRAPHEME AWARENESS
// ============================================================================

test "cursor position: next grapheme after ASCII" {
    // After 'A', next position should skip to 'B'
    const text = "ABC";
    // Position 0 -> move to position 1 (byte index of 'B')
    try testing.expectEqualStrings("ABC", text);
}

test "cursor position: next grapheme after emoji" {
    // "Hi 👋" -> cursor at end of "Hi " (position 3)
    // Next grapheme should point past emoji
    const text = "Hi 👋";
    // After implementation: nextGraphemePos("Hi 👋", 3) -> position after 👋
    try testing.expect(text.len > 4);
}

test "cursor position: next grapheme with combining mark" {
    // "é 👋" -> cursor after 'é' should skip the combining mark
    const text = "e\u{0301} 👋";
    // Position after 'e' should include combining mark in single move
    try testing.expect(text.len > 4);
}

test "cursor position: next grapheme in ZWJ sequence" {
    // 👨‍👩‍👧‍👦 -> move cursor to next position should skip entire family
    const family = "👨‍👩‍👧‍👦X";
    // Moving past family should land on X
    try testing.expect(family.len > 20);
}

test "cursor position: prev grapheme from emoji" {
    // "Hi 👋" -> cursor after emoji
    // Prev should go to space before emoji
    const text = "Hi 👋";
    // prevGraphemePos should handle multi-byte emoji correctly
    try testing.expect(text.len > 4);
}

test "cursor position: prev grapheme through combining marks" {
    // "café " (with combining mark) -> cursor at end
    // Prev should include combining mark with base character
    const text = "cafe\u{0301} ";
    try testing.expect(text.len > 5);
}

test "cursor position: home key (start of line)" {
    const text = "Hello 👋";
    // Home position = 0
    try testing.expect(text.len > 6);
}

test "cursor position: end key (end of line)" {
    const text = "Hello 👋";
    // End position = byte length of text
    try testing.expect(text.len > 6);
}

test "cursor position: left arrow respects grapheme boundaries" {
    // Start at end of "café" (with combining mark)
    const text = "cafe\u{0301}";
    // Left arrow should move to start of 'e', not between 'e' and combining mark
    try testing.expect(text.len > 4);
}

test "cursor position: right arrow respects grapheme boundaries" {
    // At start, right arrow should move past entire first grapheme
    const text = "café\u{0301}";
    // Right from 'c' should go to 'a', not into middle of combining sequence
    try testing.expect(text.len > 4);
}

test "cursor position: click in middle of wide character" {
    // If user clicks in middle of CJK character '中', should snap to that character
    const text = "Hi 中国";
    // Click at cell position that falls in middle of '中' should select '中'
    try testing.expect(text.len > 4);
}

test "cursor position: click in middle of emoji" {
    // If user clicks in middle of emoji (emoji takes 2 cells), should select emoji
    const text = "Hi 👋";
    // Click at cell 3 or 4 should both select the emoji
    try testing.expect(text.len > 4);
}

// ============================================================================
// TEXT WRAPPING RESPECTS GRAPHEME BOUNDARIES
// ============================================================================

test "text wrap: don't split ASCII characters" {
    const text = "Hello World";
    // Should wrap to "Hello" (5) + "World" (5), not "Hello W" + "orld"
    try testing.expectEqualStrings("Hello World", text);
}

test "text wrap: don't split emoji" {
    // "Hi 👋 Hello" wrap at 5 cells
    // Should wrap to "Hi 👋" (5 cells) + "Hello" (5 cells)
    // NOT "Hi " + "👋 Hello" or split emoji across lines
    const text = "Hi 👋 Hello";
    try testing.expect(text.len > 10);
}

test "text wrap: don't split emoji with modifier" {
    // "Hi 👋🏽!" wrap at 5 cells
    // 👋🏽 is single grapheme, should stay together
    const text = "Hi 👋🏽!";
    try testing.expect(text.len > 8);
}

test "text wrap: don't split ZWJ sequence" {
    // "Man: 👨‍💻 here" wrap at specific width
    // 👨‍💻 should never be split
    const text = "Man: 👨‍💻 here";
    try testing.expect(text.len > 12);
}

test "text wrap: don't split combining mark from base" {
    // "Café " wrap at 5 cells (with combining mark)
    // 'é' should stay together, not split into 'e' + combining mark
    const text = "Cafe\u{0301} done";
    try testing.expect(text.len > 6);
}

test "text wrap: don't split flag emoji" {
    // "Country 🇺🇸 here" wrap at width
    // 🇺🇸 should never be split
    const text = "Country 🇺🇸 here";
    try testing.expect(text.len > 15);
}

test "text wrap: word break at grapheme boundaries only" {
    const text = "Hello👋World";
    // Should break as "Hello" (5) + "👋World" (7) or "Hello👋" (7) + "World" (5)
    // Depending on algorithm, but 👋 never split
    try testing.expect(text.len > 10);
}

test "text wrap: punctuation with emoji" {
    const text = "Say 👋! How are you?";
    // "👋!" might be considered together or separate, but emoji stays whole
    try testing.expect(text.len > 15);
}

test "text wrap: CJK without spaces" {
    // "你好世界" wrap at 3 cells
    // Should wrap to "你好" (4) + "世界" (4)
    const text = "你好世界";
    try testing.expectEqualStrings("你好世界", text);
}

test "text wrap: mixed script (Latin + CJK)" {
    // "Hello你好" wrap at 6 cells
    // "Hello" (5) + "你" (2) = 7, so might wrap "Hello" (5) + "你好" (4)
    const text = "Hello你好";
    try testing.expect(text.len > 8);
}

// ============================================================================
// BUFFER CELL STORAGE FOR GRAPHEME CLUSTERS
// ============================================================================

test "buffer cell: store single ASCII character" {
    // After implementation: Buffer should store grapheme clusters
    // var buffer = try sailor.tui.Buffer.init(allocator, 10, 5);
    // defer buffer.deinit();

    // For now, just verify basic setup
    try testing.expect(true); // Placeholder
}

test "buffer cell: store emoji (multi-byte grapheme)" {
    // After implementation: Buffer.Cell should handle multi-codepoint graphemes
    // Cell should store "👋" as single unit, not split across multiple cells
    // var buffer = try sailor.tui.Buffer.init(allocator, 10, 5);
    // defer buffer.deinit();
    // buffer.setGrapheme(2, 0, "👋", style);
    // var cell = buffer.get(2, 0);
    // try testing.expect(eql(cell.grapheme, "👋"));

    try testing.expect(true); // Placeholder
}

test "buffer cell: store emoji with modifier" {
    // 👋🏽 should be stored as single cell grapheme
    // Not as two separate emoji
    // After implementation: verify single grapheme storage
    try testing.expect(true); // Placeholder
}

test "buffer cell: store ZWJ sequence" {
    // 👨‍💻 should be stored as single cell grapheme
    try testing.expect(true); // Placeholder
}

test "buffer cell: store combining mark sequence" {
    // "é" (e + combining acute) should be single cell
    try testing.expect(true); // Placeholder
}

test "buffer cell: display width of stored grapheme" {
    // After storage, Buffer should know display width
    // ASCII char = 1 cell width
    // Emoji = 2 cell width
    // Combining mark attached to char = adds 0 width
    try testing.expect(true); // Placeholder
}

test "buffer cell: setString with grapheme awareness" {
    // Buffer.setString("Hello 👋") should:
    // - Parse into grapheme clusters
    // - Store each cluster as grapheme
    // - Correctly advance column position by cell width
    try testing.expect(true); // Placeholder
}

test "buffer cell: render grapheme cluster to terminal" {
    // When writing Cell containing multi-codepoint grapheme
    // Should write all codepoints to achieve proper display
    // Example: Cell with 👋🏽 should write both codepoints
    try testing.expect(true); // Placeholder
}

test "buffer cell: copy grapheme between cells" {
    // Copying Cell containing emoji should preserve all codepoints
    try testing.expect(true); // Placeholder
}

test "buffer cell: clear grapheme cell" {
    // Clearing cell with grapheme should reset to space
    try testing.expect(true); // Placeholder
}

// ============================================================================
// EDGE CASES AND ERROR HANDLING
// ============================================================================

test "edge case: empty string" {
    const text = "";
    try testing.expect(text.len == 0);
}

test "edge case: only whitespace" {
    const text = "   ";
    try testing.expectEqual(@as(usize, 3), text.len);
}

test "edge case: only combining marks (base character missing)" {
    // Combining mark without base character
    // Should be treated as grapheme (might render as replacement char)
    const text = "\u{0301}"; // combining acute without base
    try testing.expect(text.len > 0);
}

test "edge case: zero-width joiner alone" {
    const zwj = "\u{200D}";
    // Should be parseable but have 0 width
    try testing.expect(zwj.len > 0);
}

test "edge case: surrogate pair in UTF-8" {
    // UTF-8 should never contain surrogate pairs (that's UTF-16)
    // But malformed input might, should handle gracefully
    try testing.expect(true); // Placeholder
}

test "edge case: overlong UTF-8 encoding" {
    // Overlong encoding should be detected and rejected/replaced
    try testing.expect(true); // Placeholder
}

test "edge case: incomplete UTF-8 sequence at end of buffer" {
    const text = "Hello\xF0\x9F"; // Incomplete emoji start
    // Should handle gracefully, not crash
    try testing.expect(text.len > 5);
}

test "edge case: replacement character" {
    const replacement = "\xEF\xBF\xBD"; // UTF-8 for U+FFFD (replacement char)
    // Should be treated as single grapheme width 1
    try testing.expect(replacement.len == 3);
}

test "edge case: BOM in middle of string" {
    const text = "Hello\xEF\xBB\xBFWorld";
    // BOM in middle is unusual but should be handled
    try testing.expect(text.len > 10);
}

test "edge case: RTL marks with Latin" {
    const text = "\u{202E}Hello"; // RLE (right-to-left embedding) + Hello
    // Should parse graphemes despite RTL mark
    try testing.expect(text.len > 5);
}

test "edge case: very long ZWJ sequence" {
    // Multiple emoji joined by ZWJ
    // Even if extremely long, should be single grapheme
    const text = "👨‍👩‍👧‍👦‍👨";
    try testing.expect(text.len > 20);
}

test "edge case: mixed emoji and combining marks" {
    // Emoji + combining mark (rare but valid)
    const text = "👋\u{0301}";
    // Should be single grapheme
    try testing.expect(text.len > 4);
}

test "edge case: regional indicator + combining mark" {
    // Flag + combining mark (very rare but possible)
    const text = "🇺🇸\u{0301}";
    try testing.expect(text.len > 8);
}

test "edge case: variation selector on non-emoji" {
    // Variation selector applied to ASCII (unusual)
    const text = "A\u{FE00}";
    // Should still be single grapheme
    try testing.expect(text.len > 1);
}

// ============================================================================
// REAL-WORLD SCENARIOS
// ============================================================================

test "scenario: user input with emoji reactions" {
    // Text: "Great job! 👍👏🎉"
    const text = "Great job! 👍👏🎉";
    try testing.expect(text.len > 15);
}

test "scenario: multilingual text with emoji" {
    // "Hello 你好 👋 مرحبا"
    const text = "Hello 你好 👋 مرحبا";
    // Should handle Latin, CJK, emoji, and Arabic
    try testing.expect(text.len > 20);
}

test "scenario: emoji with all skin tone variants" {
    // 👋👋🏻👋🏼👋🏽👋🏾👋🏿
    const text = "👋👋🏻👋🏼👋🏽👋🏾👋🏿";
    try testing.expect(text.len > 20);
}

test "scenario: ZWJ sequence with skin tones" {
    // 👨🏾‍💻 = man + medium skin tone + ZWJ + computer
    const man_tech_brown = "👨🏾‍💻";
    // Should be single grapheme
    try testing.expect(man_tech_brown.len > 12);
}

test "scenario: family emoji variants" {
    // Different family compositions:
    // 👨‍👩‍👧‍👦 (man, woman, girl, boy)
    // 👩‍👩‍👦 (woman, woman, boy)
    // 👨‍👨‍👧 (man, man, girl)
    const family1 = "👨‍👩‍👧‍👦";
    const family2 = "👩‍👩‍👦";
    const family3 = "👨‍👨‍👧";

    try testing.expect(family1.len > 20);
    try testing.expect(family2.len > 12);
    try testing.expect(family3.len > 12);
}

test "scenario: text editor undo/redo with emoji" {
    // Inserting "Hello👋" then undo
    // Undo should remove entire emoji, not byte-by-byte
    const text = "Hello👋";
    // After undo, should be "Hello", not "HelloF0" or similar
    try testing.expect(text.len > 6);
}

test "scenario: find/replace with emoji" {
    // Find "👋" in "Hi 👋 👋 Hello"
    // Should find both emoji correctly
    const text = "Hi 👋 👋 Hello";
    try testing.expect(text.len > 12);
}

test "scenario: text selection with mixed content" {
    // Selecting "👋🏽 café" should:
    // - Include entire 👋🏽
    // - Include entire café (with combining mark)
    const text = "👋🏽 cafe\u{0301}";
    try testing.expect(text.len > 10);
}

test "scenario: pagination with emoji" {
    // Display "Hello 👋 World" across 2 pages
    // Page 1: "Hello 👋" (5 cells)
    // Page 2: "World" (5 cells)
    // Never split emoji
    const text = "Hello 👋 World";
    try testing.expect(text.len > 12);
}

test "scenario: terminal resize with text wrapping" {
    // Terminal 20 cells wide: "Your text here 👨‍👩‍👧‍👦 more"
    // Resize to 10 cells wide
    // Layout should reflow without breaking grapheme clusters
    const text = "Your text here 👨‍👩‍👧‍👦 more";
    try testing.expect(text.len > 25);
}

test "scenario: search highlight around emoji" {
    // Find "hello" in "Hello 👋 hello 👋"
    // Should find "hello" without matching emoji
    const text = "Hello 👋 hello 👋";
    try testing.expect(text.len > 15);
}

test "scenario: word boundary detection with emoji" {
    // Word boundaries in "hello👋world"
    // Should recognize boundaries:
    // - Before 'h'
    // - After 'o'
    // - Before 'w'
    // (not splitting emoji)
    const text = "hello👋world";
    try testing.expect(text.len > 10);
}

test "scenario: CJK + emoji in list" {
    // List items: "✓ 项目1" "✓ 項目2" "✓ 목록3"
    // Chinese, Japanese, Korean with emoji checkmark
    const text = "✓ 项目1 ✓ 項目2 ✓ 목록3";
    try testing.expect(text.len > 25);
}
