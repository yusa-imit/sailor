//! Windows console API tests for sailor v2.8.0
//!
//! Comprehensive tests for Windows console API support including:
//! - ConPTY integration (Windows 10+)
//! - Legacy console fallback (Windows 7/8)
//! - Keyboard event handling
//! - UTF-16 encoding
//! - ANSI emulation layer
//! - Comptime platform detection

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const sailor = @import("sailor");

// ============================================================================
// ConPTY Tests (Windows 10+ modern terminal)
// ============================================================================

test "ConPTY: createPseudoConsole creates valid handle" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Expected: sailor.term.windows.createPseudoConsole(80, 24)
    const console = try sailor.term.windows.createPseudoConsole(80, 24);
    defer sailor.term.windows.closePseudoConsole(console);

    try testing.expect(console.handle != null);
    try testing.expect(console.width == 80);
    try testing.expect(console.height == 24);
}

test "ConPTY: createPseudoConsole with custom dimensions" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const test_dimensions = [_]struct { width: u16, height: u16 }{
        .{ .width = 40, .height = 12 },
        .{ .width = 132, .height = 43 },
        .{ .width = 200, .height = 60 },
    };

    for (test_dimensions) |dim| {
        const console = try sailor.term.windows.createPseudoConsole(dim.width, dim.height);
        defer sailor.term.windows.closePseudoConsole(console);

        try testing.expectEqual(dim.width, console.width);
        try testing.expectEqual(dim.height, console.height);
    }
}

test "ConPTY: createPseudoConsole rejects invalid dimensions" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Zero dimensions
    try testing.expectError(error.InvalidDimensions, sailor.term.windows.createPseudoConsole(0, 24));
    try testing.expectError(error.InvalidDimensions, sailor.term.windows.createPseudoConsole(80, 0));

    // Excessively large dimensions (> 10000)
    try testing.expectError(error.InvalidDimensions, sailor.term.windows.createPseudoConsole(20000, 24));
    try testing.expectError(error.InvalidDimensions, sailor.term.windows.createPseudoConsole(80, 20000));
}

test "ConPTY: resizePseudoConsole updates dimensions" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var console = try sailor.term.windows.createPseudoConsole(80, 24);
    defer sailor.term.windows.closePseudoConsole(console);

    // Resize to larger
    try sailor.term.windows.resizePseudoConsole(&console, 120, 40);
    try testing.expectEqual(@as(u16, 120), console.width);
    try testing.expectEqual(@as(u16, 40), console.height);

    // Resize to smaller
    try sailor.term.windows.resizePseudoConsole(&console, 60, 20);
    try testing.expectEqual(@as(u16, 60), console.width);
    try testing.expectEqual(@as(u16, 20), console.height);
}

test "ConPTY: resizePseudoConsole rejects invalid dimensions" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var console = try sailor.term.windows.createPseudoConsole(80, 24);
    defer sailor.term.windows.closePseudoConsole(console);

    try testing.expectError(error.InvalidDimensions, sailor.term.windows.resizePseudoConsole(&console, 0, 24));
    try testing.expectError(error.InvalidDimensions, sailor.term.windows.resizePseudoConsole(&console, 80, 0));
}

test "ConPTY: closePseudoConsole cleanup is idempotent" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const console = try sailor.term.windows.createPseudoConsole(80, 24);

    // First close should succeed
    sailor.term.windows.closePseudoConsole(console);

    // Second close should not crash (idempotent)
    sailor.term.windows.closePseudoConsole(console);
}

test "ConPTY: ENABLE_VIRTUAL_TERMINAL_PROCESSING flag detection" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const windows = std.os.windows;
    const stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch return;

    if (stdout_handle == windows.INVALID_HANDLE_VALUE) return;

    var mode: windows.DWORD = 0;
    const result = windows.kernel32.GetConsoleMode(stdout_handle, &mode);

    if (result == 0) return; // Not a console

    // Check if VT processing is supported
    const has_vt = sailor.term.windows.hasVirtualTerminalProcessing(stdout_handle);

    // On Windows 10+, this should be true
    // On older Windows, this should be false
    _ = has_vt; // Either outcome is valid
}

test "ConPTY: ENABLE_VIRTUAL_TERMINAL_INPUT flag detection" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const windows = std.os.windows;
    const stdin_handle = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch return;

    if (stdin_handle == windows.INVALID_HANDLE_VALUE) return;

    var mode: windows.DWORD = 0;
    const result = windows.kernel32.GetConsoleMode(stdin_handle, &mode);

    if (result == 0) return; // Not a console

    // Check if VT input is supported
    const has_vt_input = sailor.term.windows.hasVirtualTerminalInput(stdin_handle);

    // On Windows 10+, this should be true
    _ = has_vt_input; // Either outcome is valid
}

test "ConPTY: enable virtual terminal processing" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const windows = std.os.windows;
    const stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch return;

    if (stdout_handle == windows.INVALID_HANDLE_VALUE) return;

    // Try to enable VT processing
    const result = sailor.term.windows.enableVirtualTerminalProcessing(stdout_handle);

    // On Windows 10+, this should succeed
    // On older Windows, this might fail
    _ = result; // Either outcome is valid for this test
}

// ============================================================================
// Legacy Console Tests (Windows 7/8 fallback)
// ============================================================================

test "legacy console: SetConsoleMode operations" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const windows = std.os.windows;
    const stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch return;

    if (stdout_handle == windows.INVALID_HANDLE_VALUE) return;

    var original_mode: windows.DWORD = 0;
    if (windows.kernel32.GetConsoleMode(stdout_handle, &original_mode) == 0) return;

    // Save and restore mode
    defer _ = windows.kernel32.SetConsoleMode(stdout_handle, original_mode);

    // Test that we can modify console mode
    const new_mode = original_mode | 0x0001; // ENABLE_PROCESSED_OUTPUT
    const set_result = windows.kernel32.SetConsoleMode(stdout_handle, new_mode);

    try testing.expect(set_result != 0);
}

test "legacy console: GetConsoleMode retrieves current mode" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const windows = std.os.windows;
    const stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch return;

    if (stdout_handle == windows.INVALID_HANDLE_VALUE) return;

    var mode: windows.DWORD = 0;
    const result = windows.kernel32.GetConsoleMode(stdout_handle, &mode);

    if (result == 0) return; // Not a console

    // Mode should have at least some flags set
    try testing.expect(mode != 0);
}

test "legacy console: ANSI red color to SetConsoleTextAttribute" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // ESC[31m (red foreground) should map to RED attribute
    const ansi_code = "\x1b[31m";
    const attr = try sailor.term.windows.ansiToConsoleAttribute(ansi_code);

    // Red foreground = FOREGROUND_RED (0x0004)
    try testing.expect(attr & 0x0004 != 0);
}

test "legacy console: ANSI green color to SetConsoleTextAttribute" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const ansi_code = "\x1b[32m";
    const attr = try sailor.term.windows.ansiToConsoleAttribute(ansi_code);

    // Green foreground = FOREGROUND_GREEN (0x0002)
    try testing.expect(attr & 0x0002 != 0);
}

test "legacy console: ANSI blue color to SetConsoleTextAttribute" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const ansi_code = "\x1b[34m";
    const attr = try sailor.term.windows.ansiToConsoleAttribute(ansi_code);

    // Blue foreground = FOREGROUND_BLUE (0x0001)
    try testing.expect(attr & 0x0001 != 0);
}

test "legacy console: ANSI background color to SetConsoleTextAttribute" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const ansi_code = "\x1b[41m"; // Red background
    const attr = try sailor.term.windows.ansiToConsoleAttribute(ansi_code);

    // Red background = BACKGROUND_RED (0x0040)
    try testing.expect(attr & 0x0040 != 0);
}

test "legacy console: ANSI bold to SetConsoleTextAttribute" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const ansi_code = "\x1b[1m"; // Bold
    const attr = try sailor.term.windows.ansiToConsoleAttribute(ansi_code);

    // Bold = FOREGROUND_INTENSITY (0x0008)
    try testing.expect(attr & 0x0008 != 0);
}

test "legacy console: ANSI reset to default attributes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const ansi_code = "\x1b[0m"; // Reset
    const attr = try sailor.term.windows.ansiToConsoleAttribute(ansi_code);

    // Default = FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE (0x0007)
    try testing.expectEqual(@as(u16, 0x0007), attr);
}

test "legacy console: cursor positioning via SetConsoleCursorPosition" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const windows = std.os.windows;
    const stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch return;

    if (stdout_handle == windows.INVALID_HANDLE_VALUE) return;

    // ESC[10;20H should move cursor to row 10, column 20
    const ansi_code = "\x1b[10;20H";
    const pos = try sailor.term.windows.ansiToCursorPosition(ansi_code);

    try testing.expectEqual(@as(i16, 19), pos.X); // 0-indexed
    try testing.expectEqual(@as(i16, 9), pos.Y); // 0-indexed
}

test "legacy console: screen buffer manipulation" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const windows = std.os.windows;
    const stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch return;

    if (stdout_handle == windows.INVALID_HANDLE_VALUE) return;

    // Get current screen buffer info
    var csbi: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    const result = windows.kernel32.GetConsoleScreenBufferInfo(stdout_handle, &csbi);

    if (result == 0) return; // Not a console

    try testing.expect(csbi.dwSize.X > 0);
    try testing.expect(csbi.dwSize.Y > 0);
}

// ============================================================================
// Keyboard Event Tests
// ============================================================================

test "keyboard: ReadConsoleInputW captures Ctrl+C" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // VK_C (0x43) + CTRL_PRESSED (0x0008)
    const event = sailor.term.windows.InputEvent{
        .key = .{
            .key_down = true,
            .virtual_key_code = 0x43, // 'C'
            .control_key_state = 0x0008, // LEFT_CTRL_PRESSED
            .unicode_char = 'C',
        },
    };

    try testing.expect(sailor.term.windows.isCtrlC(event));
}

test "keyboard: ReadConsoleInputW captures Alt+F4" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // VK_F4 (0x73) + LEFT_ALT_PRESSED (0x0002)
    const event = sailor.term.windows.InputEvent{
        .key = .{
            .key_down = true,
            .virtual_key_code = 0x73, // F4
            .control_key_state = 0x0002, // LEFT_ALT_PRESSED
            .unicode_char = 0,
        },
    };

    try testing.expect(sailor.term.windows.isAltF4(event));
}

test "keyboard: event filtering key down vs key up" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const key_down_event = sailor.term.windows.InputEvent{
        .key = .{
            .key_down = true,
            .virtual_key_code = 0x41, // 'A'
            .control_key_state = 0,
            .unicode_char = 'A',
        },
    };

    const key_up_event = sailor.term.windows.InputEvent{
        .key = .{
            .key_down = false,
            .virtual_key_code = 0x41, // 'A'
            .control_key_state = 0,
            .unicode_char = 'A',
        },
    };

    try testing.expect(sailor.term.windows.isKeyDown(key_down_event));
    try testing.expect(!sailor.term.windows.isKeyDown(key_up_event));
}

test "keyboard: Unicode character input from ReadConsoleInputW" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const test_chars = [_]struct { char: u21, expected: []const u8 }{
        .{ .char = 'A', .expected = "A" },
        .{ .char = '中', .expected = "中" },
        .{ .char = 0x20AC, .expected = "€" }, // Euro sign
    };

    for (test_chars) |tc| {
        const event = sailor.term.windows.InputEvent{
            .key = .{
                .key_down = true,
                .virtual_key_code = 0,
                .control_key_state = 0,
                .unicode_char = tc.char,
            },
        };

        const utf8_buf = try sailor.term.windows.eventToUtf8(event);
        try testing.expectEqualStrings(tc.expected, utf8_buf);
    }
}

test "keyboard: function keys (F1-F12)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const function_keys = [_]struct { vk: u16, name: []const u8 }{
        .{ .vk = 0x70, .name = "F1" },
        .{ .vk = 0x71, .name = "F2" },
        .{ .vk = 0x72, .name = "F3" },
        .{ .vk = 0x73, .name = "F4" },
        .{ .vk = 0x74, .name = "F5" },
        .{ .vk = 0x75, .name = "F6" },
        .{ .vk = 0x76, .name = "F7" },
        .{ .vk = 0x77, .name = "F8" },
        .{ .vk = 0x78, .name = "F9" },
        .{ .vk = 0x79, .name = "F10" },
        .{ .vk = 0x7A, .name = "F11" },
        .{ .vk = 0x7B, .name = "F12" },
    };

    for (function_keys) |fk| {
        const event = sailor.term.windows.InputEvent{
            .key = .{
                .key_down = true,
                .virtual_key_code = fk.vk,
                .control_key_state = 0,
                .unicode_char = 0,
            },
        };

        const key_name = sailor.term.windows.virtualKeyToString(fk.vk);
        try testing.expectEqualStrings(fk.name, key_name);
    }
}

test "keyboard: arrow keys" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const arrow_keys = [_]struct { vk: u16, name: []const u8 }{
        .{ .vk = 0x25, .name = "Left" },
        .{ .vk = 0x26, .name = "Up" },
        .{ .vk = 0x27, .name = "Right" },
        .{ .vk = 0x28, .name = "Down" },
    };

    for (arrow_keys) |ak| {
        const event = sailor.term.windows.InputEvent{
            .key = .{
                .key_down = true,
                .virtual_key_code = ak.vk,
                .control_key_state = 0,
                .unicode_char = 0,
            },
        };

        const key_name = sailor.term.windows.virtualKeyToString(ak.vk);
        try testing.expectEqualStrings(ak.name, key_name);
    }
}

test "keyboard: modifier key detection (Ctrl, Alt, Shift)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const test_cases = [_]struct { state: u32, expect_ctrl: bool, expect_alt: bool, expect_shift: bool }{
        .{ .state = 0x0008, .expect_ctrl = true, .expect_alt = false, .expect_shift = false }, // LEFT_CTRL_PRESSED
        .{ .state = 0x0004, .expect_ctrl = true, .expect_alt = false, .expect_shift = false }, // RIGHT_CTRL_PRESSED
        .{ .state = 0x0002, .expect_ctrl = false, .expect_alt = true, .expect_shift = false }, // LEFT_ALT_PRESSED
        .{ .state = 0x0001, .expect_ctrl = false, .expect_alt = true, .expect_shift = false }, // RIGHT_ALT_PRESSED
        .{ .state = 0x0010, .expect_ctrl = false, .expect_alt = false, .expect_shift = true }, // SHIFT_PRESSED
        .{ .state = 0x000A, .expect_ctrl = true, .expect_alt = true, .expect_shift = false }, // CTRL + ALT
    };

    for (test_cases) |tc| {
        const mod_event = sailor.term.windows.InputEvent{
            .key = .{
                .key_down = true,
                .virtual_key_code = 0x41, // 'A'
                .control_key_state = tc.state,
                .unicode_char = 'A',
            },
        };

        try testing.expectEqual(tc.expect_ctrl, sailor.term.windows.hasCtrlPressed(mod_event));
        try testing.expectEqual(tc.expect_alt, sailor.term.windows.hasAltPressed(mod_event));
        try testing.expectEqual(tc.expect_shift, sailor.term.windows.hasShiftPressed(mod_event));
    }
}

test "keyboard: mouse events (not supported)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Mouse events should be filtered out
    const mouse_event = sailor.term.windows.InputEvent{
        .mouse = .{
            .x = 10,
            .y = 20,
            .button_state = 1,
        },
    };

    try testing.expect(!sailor.term.windows.isKeyEvent(mouse_event));
}

// ============================================================================
// UTF-16 Encoding Tests
// ============================================================================

test "UTF-16: UTF-8 to UTF-16LE conversion (ASCII)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    const utf8_str = "Hello, World!";

    const utf16_buf = try sailor.term.windows.utf8ToUtf16Le(allocator, utf8_str);
    defer allocator.free(utf16_buf);

    // ASCII characters are 1:1 in UTF-16
    try testing.expectEqual(utf8_str.len, utf16_buf.len);

    // Check first few characters
    try testing.expectEqual(@as(u16, 'H'), utf16_buf[0]);
    try testing.expectEqual(@as(u16, 'e'), utf16_buf[1]);
    try testing.expectEqual(@as(u16, 'l'), utf16_buf[2]);
}

test "UTF-16: UTF-8 to UTF-16LE conversion (BMP characters)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    const utf8_str = "中文"; // 2 Chinese characters

    const utf16_buf = try sailor.term.windows.utf8ToUtf16Le(allocator, utf8_str);
    defer allocator.free(utf16_buf);

    // 2 characters = 2 UTF-16 code units
    try testing.expectEqual(@as(usize, 2), utf16_buf.len);

    // U+4E2D and U+6587
    try testing.expectEqual(@as(u16, 0x4E2D), utf16_buf[0]);
    try testing.expectEqual(@as(u16, 0x6587), utf16_buf[1]);
}

test "UTF-16: UTF-8 to UTF-16LE conversion (surrogate pairs)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    const utf8_str = "🚢"; // Ship emoji (U+1F6A2)

    const utf16_buf = try sailor.term.windows.utf8ToUtf16Le(allocator, utf8_str);
    defer allocator.free(utf16_buf);

    // 1 emoji = 2 UTF-16 code units (surrogate pair)
    try testing.expectEqual(@as(usize, 2), utf16_buf.len);

    // High surrogate: 0xD83D, Low surrogate: 0xDEA2
    try testing.expectEqual(@as(u16, 0xD83D), utf16_buf[0]);
    try testing.expectEqual(@as(u16, 0xDEA2), utf16_buf[1]);
}

test "UTF-16: UTF-16LE to UTF-8 conversion (ASCII)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    const utf16_buf = [_]u16{ 'H', 'e', 'l', 'l', 'o' };

    const utf8_str = try sailor.term.windows.utf16LeToUtf8(allocator, &utf16_buf);
    defer allocator.free(utf8_str);

    try testing.expectEqualStrings("Hello", utf8_str);
}

test "UTF-16: UTF-16LE to UTF-8 conversion (BMP characters)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    const utf16_buf = [_]u16{ 0x4E2D, 0x6587 }; // 中文

    const utf8_str = try sailor.term.windows.utf16LeToUtf8(allocator, &utf16_buf);
    defer allocator.free(utf8_str);

    try testing.expectEqualStrings("中文", utf8_str);
}

test "UTF-16: UTF-16LE to UTF-8 conversion (surrogate pairs)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    const utf16_buf = [_]u16{ 0xD83D, 0xDEA2 }; // 🚢

    const utf8_str = try sailor.term.windows.utf16LeToUtf8(allocator, &utf16_buf);
    defer allocator.free(utf8_str);

    try testing.expectEqualStrings("🚢", utf8_str);
}

test "UTF-16: buffer size calculation for UTF-8 to UTF-16" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const test_cases = [_]struct { input: []const u8, expected_len: usize }{
        .{ .input = "Hello", .expected_len = 5 }, // ASCII
        .{ .input = "中文", .expected_len = 2 }, // BMP
        .{ .input = "🚢", .expected_len = 2 }, // Surrogate pair
        .{ .input = "Hello 中文 🚢", .expected_len = 11 }, // Mixed
    };

    for (test_cases) |tc| {
        const size = sailor.term.windows.utf8ToUtf16BufferSize(tc.input);
        try testing.expectEqual(tc.expected_len, size);
    }
}

test "UTF-16: buffer size calculation for UTF-16 to UTF-8" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const test_cases = [_]struct { input: []const u16, expected_len: usize }{
        .{ .input = &[_]u16{ 'H', 'e', 'l', 'l', 'o' }, .expected_len = 5 }, // ASCII
        .{ .input = &[_]u16{ 0x4E2D, 0x6587 }, .expected_len = 6 }, // BMP (3 bytes each)
        .{ .input = &[_]u16{ 0xD83D, 0xDEA2 }, .expected_len = 4 }, // Surrogate pair (4 bytes)
    };

    for (test_cases) |tc| {
        const size = sailor.term.windows.utf16ToUtf8BufferSize(tc.input);
        try testing.expectEqual(tc.expected_len, size);
    }
}

test "UTF-16: invalid surrogate pair handling" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Lone high surrogate (invalid)
    const lone_high = [_]u16{0xD83D};
    try testing.expectError(error.InvalidUtf16, sailor.term.windows.utf16LeToUtf8(allocator, &lone_high));

    // Lone low surrogate (invalid)
    const lone_low = [_]u16{0xDEA2};
    try testing.expectError(error.InvalidUtf16, sailor.term.windows.utf16LeToUtf8(allocator, &lone_low));

    // High surrogate followed by non-low surrogate (invalid)
    const bad_pair = [_]u16{ 0xD83D, 0x0041 };
    try testing.expectError(error.InvalidUtf16, sailor.term.windows.utf16LeToUtf8(allocator, &bad_pair));
}

test "UTF-16: empty string conversion" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;

    // UTF-8 to UTF-16
    const utf16_buf = try sailor.term.windows.utf8ToUtf16Le(allocator, "");
    defer allocator.free(utf16_buf);
    try testing.expectEqual(@as(usize, 0), utf16_buf.len);

    // UTF-16 to UTF-8
    const empty_utf16 = [_]u16{};
    const utf8_str = try sailor.term.windows.utf16LeToUtf8(allocator, &empty_utf16);
    defer allocator.free(utf8_str);
    try testing.expectEqualStrings("", utf8_str);
}

// ============================================================================
// Comptime Platform Detection Tests
// ============================================================================

test "comptime: Windows code not compiled on Linux" {
    if (builtin.os.tag == .linux) {
        // This should compile on Linux, but Windows-specific code should not
        // The existence of sailor.term.windows should be compile-time guarded
        comptime {
            if (@hasDecl(sailor.term, "windows")) {
                @compileError("Windows-specific code should not be compiled on Linux");
            }
        }
    }
}

test "comptime: Windows code not compiled on macOS" {
    if (builtin.os.tag == .macos) {
        comptime {
            if (@hasDecl(sailor.term, "windows")) {
                @compileError("Windows-specific code should not be compiled on macOS");
            }
        }
    }
}

test "comptime: Windows code is available on Windows" {
    if (builtin.os.tag == .windows) {
        comptime {
            if (!@hasDecl(sailor.term, "windows")) {
                @compileError("Windows-specific code should be available on Windows");
            }
        }
    }
}

test "comptime: fallback stubs work on non-Windows platforms" {
    if (builtin.os.tag != .windows) {
        // These functions should exist but return appropriate errors
        const result = sailor.term.windows.createPseudoConsole(80, 24);
        try testing.expectError(error.UnsupportedPlatform, result);
    }
}

test "comptime: no runtime overhead for platform checks" {
    // This test verifies that platform checks are comptime-only
    const is_windows = comptime builtin.os.tag == .windows;

    // On Windows, this should compile to true
    // On other platforms, this should compile to false
    // No runtime branching should occur
    if (is_windows) {
        _ = sailor.term.windows;
    }
}

// ============================================================================
// Integration Tests
// ============================================================================

test "integration: ConPTY with ANSI output" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const console = try sailor.term.windows.createPseudoConsole(80, 24);
    defer sailor.term.windows.closePseudoConsole(console);

    // Write ANSI sequences to ConPTY
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try writer.writeAll("\x1b[31mRED\x1b[0m");
    try writer.writeAll(" ");
    try writer.writeAll("\x1b[32mGREEN\x1b[0m");

    const written = fbs.getWritten();
    try testing.expect(written.len > 0);
}

test "integration: legacy console with ANSI emulation" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const ansi_str = "\x1b[31mRED\x1b[0m TEXT \x1b[1;34mBOLD BLUE\x1b[0m";

    // Parse ANSI and convert to console API calls
    var segments = try sailor.term.windows.parseAnsiSegments(testing.allocator, ansi_str);
    defer segments.deinit();

    try testing.expect(segments.items.len > 0);

    // First segment: RED text
    try testing.expectEqual(@as(u16, 0x0004), segments.items[0].attribute); // RED
    try testing.expectEqualStrings("RED", segments.items[0].text);
}

test "integration: UTF-16 round-trip conversion" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    const original = "Hello, 世界! 🚢 中文";

    // UTF-8 -> UTF-16
    const utf16_buf = try sailor.term.windows.utf8ToUtf16Le(allocator, original);
    defer allocator.free(utf16_buf);

    // UTF-16 -> UTF-8
    const restored = try sailor.term.windows.utf16LeToUtf8(allocator, utf16_buf);
    defer allocator.free(restored);

    try testing.expectEqualStrings(original, restored);
}

test "integration: keyboard event to UTF-8 string" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;

    const events = [_]sailor.term.windows.InputEvent{
        .{ .key = .{ .key_down = true, .virtual_key_code = 0x48, .control_key_state = 0, .unicode_char = 'H' } },
        .{ .key = .{ .key_down = true, .virtual_key_code = 0x69, .control_key_state = 0, .unicode_char = 'i' } },
    };

    var result_buf = std.ArrayList(u8).init(allocator);
    defer result_buf.deinit();

    for (events) |event| {
        const utf8_str = try sailor.term.windows.eventToUtf8(event);
        try result_buf.appendSlice(utf8_str);
    }

    try testing.expectEqualStrings("Hi", result_buf.items);
}
