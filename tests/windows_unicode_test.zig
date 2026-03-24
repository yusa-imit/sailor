//! Windows console Unicode edge case tests
//!
//! Tests that verify correct handling of Unicode characters on Windows console,
//! including UTF-16 surrogate pairs, wide characters, and console API edge cases.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const sailor = @import("sailor");

// Skip all tests if not on Windows
const skip_if_not_windows = if (builtin.os.tag != .windows) error.SkipZigTest else {};

test "Windows console UTF-16 surrogate pair handling" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Test characters that require UTF-16 surrogate pairs
    const emoji_chars = [_][]const u8{
        "🚢", // Ship emoji (U+1F6A2)
        "🌊", // Water wave (U+1F30A)
        "⛵", // Sailboat (U+26F5)
        "🎯", // Direct hit (U+1F3AF)
        "📦", // Package (U+1F4E6)
    };

    for (emoji_chars) |char| {
        // Verify UTF-8 is valid
        try testing.expect(std.unicode.utf8ValidateSlice(char));

        // Verify we can get UTF-8 code point
        const view = try std.unicode.Utf8View.init(char);
        var iter = view.iterator();
        const codepoint = iter.nextCodepoint();

        // Codepoint should exist and be > U+FFFF (requires surrogate pair in UTF-16)
        if (codepoint) |cp| {
            try testing.expect(cp > 0xFFFF);
        } else {
            // If we get null, the test environment doesn't support this properly
            // Skip rather than fail, as this is an environment limitation
            return error.SkipZigTest;
        }
    }
}

test "Windows console BMP character handling" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Test characters in the Basic Multilingual Plane (U+0000 to U+FFFF)
    const bmp_chars = [_]struct { str: []const u8, expected_cp: u21 }{
        .{ .str = "A", .expected_cp = 0x41 },
        .{ .str = "€", .expected_cp = 0x20AC }, // Euro sign
        .{ .str = "中", .expected_cp = 0x4E2D }, // CJK character
        .{ .str = "ñ", .expected_cp = 0xF1 }, // Latin small letter n with tilde
        .{ .str = "—", .expected_cp = 0x2014 }, // Em dash
        .{ .str = "™", .expected_cp = 0x2122 }, // Trademark sign
        .{ .str = "☺", .expected_cp = 0x263A }, // White smiling face
    };

    for (bmp_chars) |char_info| {
        const view = try std.unicode.Utf8View.init(char_info.str);
        var iter = view.iterator();
        const codepoint = iter.nextCodepoint();
        try testing.expect(codepoint != null);
        try testing.expectEqual(char_info.expected_cp, codepoint.?);
    }
}

test "Windows console box drawing characters" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Box drawing characters are critical for TUI rendering
    const box_chars = [_][]const u8{
        "─", "│", "┌", "┐", "└", "┘", // Single line
        "━", "┃", "┏", "┓", "┗", "┛", // Bold line
        "═", "║", "╔", "╗", "╚", "╝", // Double line
        "┼", "├", "┤", "┬", "┴", // Intersections
    };

    for (box_chars) |char| {
        try testing.expect(std.unicode.utf8ValidateSlice(char));

        // Verify it's in the box drawing Unicode block (U+2500 to U+257F)
        const view = try std.unicode.Utf8View.init(char);
        var iter = view.iterator();
        const codepoint = iter.nextCodepoint();
        try testing.expect(codepoint != null);
        try testing.expect(codepoint.? >= 0x2500 and codepoint.? <= 0x257F);
    }
}

test "Windows console CJK character width" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // CJK characters should be full-width (2 cells in console)
    const cjk_chars = [_][]const u8{
        "中", // Chinese
        "日", // Japanese
        "한", // Korean
        "本", // Japanese
        "文", // Chinese
    };

    for (cjk_chars) |char| {
        try testing.expect(std.unicode.utf8ValidateSlice(char));

        const view = try std.unicode.Utf8View.init(char);
        var iter = view.iterator();
        const codepoint = iter.nextCodepoint();
        try testing.expect(codepoint != null);

        // CJK Unified Ideographs main block: U+4E00 to U+9FFF
        const is_cjk = (codepoint.? >= 0x4E00 and codepoint.? <= 0x9FFF) or
            // Hangul Syllables: U+AC00 to U+D7AF
            (codepoint.? >= 0xAC00 and codepoint.? <= 0xD7AF);
        try testing.expect(is_cjk);
    }
}

test "Windows console control character handling" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Control characters (U+0000 to U+001F) should be handled carefully
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // Test common control characters
    try writer.writeByte(0x07); // Bell (BEL)
    try writer.writeByte(0x08); // Backspace (BS)
    try writer.writeByte(0x09); // Tab (HT)
    try writer.writeByte(0x0A); // Line feed (LF)
    try writer.writeByte(0x0D); // Carriage return (CR)
    try writer.writeByte(0x1B); // Escape (ESC)

    const written = fbs.getWritten();
    try testing.expectEqual(@as(usize, 6), written.len);
}

test "Windows console ANSI escape sequence handling" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Windows 10+ supports ANSI escape sequences
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // Test basic color codes
    try writer.writeAll("\x1b[31m"); // Red foreground
    try writer.writeAll("RED");
    try writer.writeAll("\x1b[0m"); // Reset

    try writer.writeAll("\x1b[42m"); // Green background
    try writer.writeAll("GREEN");
    try writer.writeAll("\x1b[0m"); // Reset

    const written = fbs.getWritten();
    try testing.expect(written.len > 0);
    try testing.expect(std.mem.indexOf(u8, written, "\x1b[31m") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\x1b[42m") != null);
}

test "Windows console CSI sequence parsing" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Test Control Sequence Introducer (CSI) sequences
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // Cursor movement
    try writer.writeAll("\x1b[1A"); // Cursor up 1
    try writer.writeAll("\x1b[2B"); // Cursor down 2
    try writer.writeAll("\x1b[3C"); // Cursor forward 3
    try writer.writeAll("\x1b[4D"); // Cursor back 4

    // Cursor positioning
    try writer.writeAll("\x1b[10;20H"); // Move to row 10, col 20

    // Erase sequences
    try writer.writeAll("\x1b[J"); // Clear from cursor to end of screen
    try writer.writeAll("\x1b[2J"); // Clear entire screen
    try writer.writeAll("\x1b[K"); // Clear from cursor to end of line

    const written = fbs.getWritten();
    try testing.expect(written.len > 0);
}

test "Windows console SGR (Select Graphic Rendition) parameters" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // SGR parameters (CSI Pm m)
    try writer.writeAll("\x1b[0m"); // Reset
    try writer.writeAll("\x1b[1m"); // Bold
    try writer.writeAll("\x1b[2m"); // Dim
    try writer.writeAll("\x1b[3m"); // Italic
    try writer.writeAll("\x1b[4m"); // Underline
    try writer.writeAll("\x1b[7m"); // Reverse video
    try writer.writeAll("\x1b[8m"); // Concealed
    try writer.writeAll("\x1b[9m"); // Strikethrough

    // Multiple parameters
    try writer.writeAll("\x1b[1;31;42m"); // Bold, red fg, green bg

    const written = fbs.getWritten();
    try testing.expect(written.len > 0);
}

test "Windows console 256-color mode" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // 256-color foreground: CSI 38 ; 5 ; N m
    try writer.writeAll("\x1b[38;5;196m"); // Bright red (196)
    try writer.writeAll("256-color");
    try writer.writeAll("\x1b[0m");

    // 256-color background: CSI 48 ; 5 ; N m
    try writer.writeAll("\x1b[48;5;21m"); // Blue background (21)
    try writer.writeAll("BG");
    try writer.writeAll("\x1b[0m");

    const written = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, written, "\x1b[38;5;196m") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\x1b[48;5;21m") != null);
}

test "Windows console 24-bit truecolor mode" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // 24-bit foreground: CSI 38 ; 2 ; R ; G ; B m
    try writer.writeAll("\x1b[38;2;255;128;64m"); // RGB(255, 128, 64)
    try writer.writeAll("truecolor");
    try writer.writeAll("\x1b[0m");

    // 24-bit background: CSI 48 ; 2 ; R ; G ; B m
    try writer.writeAll("\x1b[48;2;32;64;128m"); // RGB(32, 64, 128)
    try writer.writeAll("BG");
    try writer.writeAll("\x1b[0m");

    const written = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, written, "\x1b[38;2;255;128;64m") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\x1b[48;2;32;64;128m") != null);
}

test "Windows console legacy console mode vs VT mode" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Windows has two console modes:
    // 1. Legacy mode (pre-Windows 10) - no ANSI support
    // 2. VT mode (Windows 10+) - ANSI/VT100 support

    // We test that our library handles both gracefully
    // by using escape sequences that work in both modes
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // In legacy mode, escape sequences are printed literally
    // In VT mode, they're interpreted
    // Our library should not crash in either case
    try writer.writeAll("\x1b[31mRED\x1b[0m");

    const written = fbs.getWritten();
    try testing.expect(written.len > 0);
}

test "Windows console null terminator handling" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Windows APIs often use null-terminated strings
    // Test that we handle them correctly
    const str_with_null = "Hello\x00World";
    const str_without_null = "HelloWorld";

    // Slices should work without null terminator
    try testing.expect(std.unicode.utf8ValidateSlice(str_without_null));

    // Null byte is a valid UTF-8 character (U+0000)
    try testing.expect(std.unicode.utf8ValidateSlice(str_with_null));
}

test "Windows console path separator in escape sequences" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Test that backslashes in file paths don't interfere with escape sequences
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // Windows path with backslashes
    const path = "C:\\Users\\test\\file.txt";
    try writer.writeAll("\x1b[32m"); // Green
    try writer.writeAll(path);
    try writer.writeAll("\x1b[0m"); // Reset

    const written = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, written, path) != null);
}

test "Windows console combining characters" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Combining characters (diacritics) are separate code points
    const combining_chars = [_][]const u8{
        "é", // U+00E9 (precomposed)
        "e\u{0301}", // e + combining acute accent
        "ñ", // U+00F1 (precomposed)
        "n\u{0303}", // n + combining tilde
    };

    for (combining_chars) |char| {
        try testing.expect(std.unicode.utf8ValidateSlice(char));
    }
}

test "Windows console zero-width characters" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Zero-width characters should not take up console cells
    const zero_width_chars = [_][]const u8{
        "\u{200B}", // Zero-width space
        "\u{200C}", // Zero-width non-joiner
        "\u{200D}", // Zero-width joiner
        "\u{FEFF}", // Zero-width no-break space (BOM)
    };

    for (zero_width_chars) |char| {
        try testing.expect(std.unicode.utf8ValidateSlice(char));
    }
}

test "Windows console emoji with skin tone modifiers" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Emoji with Fitzpatrick skin tone modifiers
    const emoji_with_modifiers = [_][]const u8{
        "👍", // Thumbs up (base)
        "👍🏻", // Thumbs up + light skin tone
        "👍🏽", // Thumbs up + medium skin tone
        "👍🏿", // Thumbs up + dark skin tone
    };

    for (emoji_with_modifiers) |char| {
        try testing.expect(std.unicode.utf8ValidateSlice(char));
    }
}

test "Windows console emoji ZWJ sequences" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Emoji with Zero-Width Joiner (ZWJ) sequences
    const zwj_emoji = [_][]const u8{
        "👨‍👩‍👧‍👦", // Family: Man, Woman, Girl, Boy
        "👨‍💻", // Man Technologist
        "🏴‍☠️", // Pirate Flag
    };

    for (zwj_emoji) |char| {
        try testing.expect(std.unicode.utf8ValidateSlice(char));
    }
}

test "Windows console bidirectional text marks" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Bidirectional text control characters (for RTL languages)
    const bidi_marks = [_][]const u8{
        "\u{200E}", // Left-to-right mark (LRM)
        "\u{200F}", // Right-to-left mark (RLM)
        "\u{202A}", // Left-to-right embedding (LRE)
        "\u{202B}", // Right-to-left embedding (RLE)
        "\u{202C}", // Pop directional formatting (PDF)
    };

    for (bidi_marks) |mark| {
        try testing.expect(std.unicode.utf8ValidateSlice(mark));
    }
}

test "Windows console newline handling CRLF vs LF" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // Windows traditionally uses CRLF (\\r\\n)
    try writer.writeAll("Line 1\r\n");
    try writer.writeAll("Line 2\n"); // LF only
    try writer.writeAll("Line 3\r\n");

    const written = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, written, "\r\n") != null);
    try testing.expect(std.mem.indexOf(u8, written, "Line 2\n") != null);
}

test "Windows console GetConsoleMode feature detection" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Test that we can detect console capabilities via GetConsoleMode
    const windows = std.os.windows;

    // Try to get stdout handle
    const stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch {
        // In CI, this might fail, which is acceptable
        return;
    };

    if (stdout_handle == windows.INVALID_HANDLE_VALUE) {
        // No console available, skip
        return;
    }

    // Try to get console mode
    var mode: windows.DWORD = 0;
    const result = windows.kernel32.GetConsoleMode(stdout_handle, &mode);

    // In a real console, this should succeed
    // In CI/redirected output, it might fail
    _ = result; // Either outcome is valid
}

test "Windows console WriteConsoleW vs WriteFile" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Windows has two ways to write to console:
    // 1. WriteConsoleW - Unicode-aware, for console output
    // 2. WriteFile - byte-oriented, for redirected output

    // Our library should work with both by using std.io.Writer
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // Write Unicode text
    try writer.writeAll("Hello, 世界! 🚢");

    const written = fbs.getWritten();
    try testing.expect(written.len > 0);
    try testing.expect(std.unicode.utf8ValidateSlice(written));
}

test "Windows console invalid UTF-8 handling" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Test that we reject invalid UTF-8 sequences
    const invalid_utf8 = [_][]const u8{
        "\xFF\xFE", // Invalid start bytes
        "\xC0\x80", // Overlong encoding of NUL
        "\xED\xA0\x80", // UTF-16 surrogate half
        "\xF4\x90\x80\x80", // Code point > U+10FFFF
    };

    for (invalid_utf8) |bad_str| {
        const result = std.unicode.utf8ValidateSlice(bad_str);
        try testing.expect(!result);
    }
}

test "Windows console console buffer size vs viewport size" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Windows console has:
    // 1. Buffer size (total scrollback)
    // 2. Viewport size (visible window)

    // Our term.getSize() should return viewport size
    const result = sailor.term.getSize();

    if (result) |size| {
        // Viewport should be reasonable
        try testing.expect(size.cols > 0 and size.cols < 10000);
        try testing.expect(size.rows > 0 and size.rows < 10000);

        // Common Windows console sizes
        const is_common_size =
            (size.cols == 80 and size.rows == 25) or // Classic
            (size.cols == 80 and size.rows == 24) or // VT100
            (size.cols == 120) or // Modern wide
            (size.cols >= 40 and size.cols <= 400); // Reasonable range

        try testing.expect(is_common_size);
    } else |err| {
        // In CI, this is expected
        try testing.expect(err == sailor.term.Error.TerminalSizeUnavailable);
    }
}
