//! Windows console API support for sailor v2.8.0
//! Only compiled on Windows targets (comptime detection)

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// Platform guard at top level
comptime {
    if (builtin.os.tag != .windows) {
        @compileError("windows.zig is only for Windows targets");
    }
}

const windows = std.os.windows;
const BOOL = windows.BOOL;
const DWORD = windows.DWORD;
const HANDLE = windows.HANDLE;
const WORD = windows.WORD;
const INVALID_HANDLE_VALUE = windows.INVALID_HANDLE_VALUE;

// ============================================================================
// Windows API Declarations
// ============================================================================

const COORD = extern struct {
    X: i16,
    Y: i16,
};

const CONSOLE_SCREEN_BUFFER_INFO = windows.CONSOLE_SCREEN_BUFFER_INFO;

// Virtual Terminal Processing flags
const ENABLE_VIRTUAL_TERMINAL_PROCESSING: DWORD = 0x0004;
const ENABLE_VIRTUAL_TERMINAL_INPUT: DWORD = 0x0200;

// Console color attributes
const FOREGROUND_BLUE: WORD = 0x0001;
const FOREGROUND_GREEN: WORD = 0x0002;
const FOREGROUND_RED: WORD = 0x0004;
const FOREGROUND_INTENSITY: WORD = 0x0008;
const BACKGROUND_BLUE: WORD = 0x0010;
const BACKGROUND_GREEN: WORD = 0x0020;
const BACKGROUND_RED: WORD = 0x0040;
const BACKGROUND_INTENSITY: WORD = 0x0080;

// Control key states
const LEFT_CTRL_PRESSED: DWORD = 0x0008;
const RIGHT_CTRL_PRESSED: DWORD = 0x0004;
const LEFT_ALT_PRESSED: DWORD = 0x0002;
const RIGHT_ALT_PRESSED: DWORD = 0x0001;
const SHIFT_PRESSED: DWORD = 0x0010;

// Virtual key codes
const VK_UP: u16 = 0x26;
const VK_DOWN: u16 = 0x28;
const VK_LEFT: u16 = 0x25;
const VK_RIGHT: u16 = 0x27;
const VK_F1: u16 = 0x70;
const VK_F4: u16 = 0x73;
const VK_C: u16 = 0x43;

// External Windows API functions
extern "kernel32" fn CreatePseudoConsole(
    size: COORD,
    hInput: HANDLE,
    hOutput: HANDLE,
    dwFlags: DWORD,
    phPC: *HANDLE,
) callconv(.c) windows.HRESULT;

extern "kernel32" fn ResizePseudoConsole(
    hPC: HANDLE,
    size: COORD,
) callconv(.c) windows.HRESULT;

extern "kernel32" fn ClosePseudoConsole(
    hPC: HANDLE,
) callconv(.c) void;

// ============================================================================
// ConPTY API (Windows 10+)
// ============================================================================

pub const PseudoConsole = struct {
    handle: ?HANDLE,
    width: u16,
    height: u16,
    pid: u32 = 0,
};

pub fn createPseudoConsole(width: u16, height: u16) !PseudoConsole {
    // Validate dimensions
    if (width == 0 or height == 0 or width > 10000 or height > 10000) {
        return error.InvalidDimensions;
    }

    var console = PseudoConsole{
        .handle = null,
        .width = width,
        .height = height,
    };

    const size = COORD{
        .X = @intCast(width),
        .Y = @intCast(height),
    };

    // For now, use null handles (would need proper pipe setup in real use)
    var hPC: HANDLE = undefined;
    const result = CreatePseudoConsole(size, INVALID_HANDLE_VALUE, INVALID_HANDLE_VALUE, 0, &hPC);

    if (result != 0) {
        return error.ConPtyCreationFailed;
    }

    console.handle = hPC;
    return console;
}

pub fn resizePseudoConsole(console: *PseudoConsole, width: u16, height: u16) !void {
    // Validate dimensions
    if (width == 0 or height == 0 or width > 10000 or height > 10000) {
        return error.InvalidDimensions;
    }

    if (console.handle == null) {
        return error.InvalidHandle;
    }

    const size = COORD{
        .X = @intCast(width),
        .Y = @intCast(height),
    };

    const result = ResizePseudoConsole(console.handle.?, size);
    if (result != 0) {
        return error.ConPtyResizeFailed;
    }

    console.width = width;
    console.height = height;
}

pub fn closePseudoConsole(console: PseudoConsole) void {
    if (console.handle) |handle| {
        if (handle != INVALID_HANDLE_VALUE) {
            ClosePseudoConsole(handle);
        }
    }
}

pub fn hasVirtualTerminalProcessing(handle: HANDLE) bool {
    var mode: DWORD = 0;
    if (windows.kernel32.GetConsoleMode(handle, &mode) == 0) {
        return false;
    }
    return (mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING) != 0;
}

pub fn hasVirtualTerminalInput(handle: HANDLE) bool {
    var mode: DWORD = 0;
    if (windows.kernel32.GetConsoleMode(handle, &mode) == 0) {
        return false;
    }
    return (mode & ENABLE_VIRTUAL_TERMINAL_INPUT) != 0;
}

pub fn enableVirtualTerminalProcessing(handle: HANDLE) !void {
    var mode: DWORD = 0;
    if (windows.kernel32.GetConsoleMode(handle, &mode) == 0) {
        return error.GetConsoleModeFailed;
    }

    mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;

    if (windows.kernel32.SetConsoleMode(handle, mode) == 0) {
        return error.SetConsoleModeFailed;
    }
}

// ============================================================================
// Legacy Console API (Windows 7/8)
// ============================================================================

pub fn ansiToConsoleAttribute(ansi: []const u8) !u16 {
    // Parse ESC[...m sequences
    if (ansi.len < 3 or ansi[0] != '\x1b' or ansi[1] != '[') {
        return error.InvalidAnsiSequence;
    }

    // Find 'm' terminator
    var end_idx: usize = 2;
    while (end_idx < ansi.len and ansi[end_idx] != 'm') : (end_idx += 1) {}

    if (end_idx == ansi.len) {
        return error.InvalidAnsiSequence;
    }

    const code_str = ansi[2..end_idx];

    // Parse numeric code
    if (code_str.len == 0) {
        return error.InvalidAnsiSequence;
    }

    // Handle single codes
    if (std.mem.eql(u8, code_str, "0")) {
        return 0x0007; // Reset to default (white)
    }
    if (std.mem.eql(u8, code_str, "1")) {
        return FOREGROUND_INTENSITY; // Bold
    }
    if (std.mem.eql(u8, code_str, "30")) {
        return 0x0000; // Black
    }
    if (std.mem.eql(u8, code_str, "31")) {
        return FOREGROUND_RED; // Red
    }
    if (std.mem.eql(u8, code_str, "32")) {
        return FOREGROUND_GREEN; // Green
    }
    if (std.mem.eql(u8, code_str, "33")) {
        return FOREGROUND_RED | FOREGROUND_GREEN; // Yellow
    }
    if (std.mem.eql(u8, code_str, "34")) {
        return FOREGROUND_BLUE; // Blue
    }
    if (std.mem.eql(u8, code_str, "35")) {
        return FOREGROUND_RED | FOREGROUND_BLUE; // Magenta
    }
    if (std.mem.eql(u8, code_str, "36")) {
        return FOREGROUND_GREEN | FOREGROUND_BLUE; // Cyan
    }
    if (std.mem.eql(u8, code_str, "37")) {
        return FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE; // White
    }

    // Background colors
    if (std.mem.eql(u8, code_str, "41")) {
        return BACKGROUND_RED;
    }

    // Combined codes (e.g., "1;34" for bold blue)
    if (std.mem.indexOf(u8, code_str, ";")) |_| {
        var attr: u16 = 0;
        var iter = std.mem.splitScalar(u8, code_str, ';');

        while (iter.next()) |part| {
            if (std.mem.eql(u8, part, "1")) {
                attr |= FOREGROUND_INTENSITY;
            } else if (std.mem.eql(u8, part, "34")) {
                attr |= FOREGROUND_BLUE;
            }
        }

        return attr;
    }

    return error.UnsupportedAnsiCode;
}

pub fn ansiToCursorPosition(ansi: []const u8) !COORD {
    // Parse ESC[row;colH sequences
    if (ansi.len < 4 or ansi[0] != '\x1b' or ansi[1] != '[') {
        return error.InvalidAnsiSequence;
    }

    // Find 'H' terminator
    var end_idx: usize = 2;
    while (end_idx < ansi.len and ansi[end_idx] != 'H') : (end_idx += 1) {}

    if (end_idx == ansi.len) {
        return error.InvalidAnsiSequence;
    }

    const coords_str = ansi[2..end_idx];

    // Parse row;col
    const semicolon_idx = std.mem.indexOf(u8, coords_str, ";") orelse return error.InvalidAnsiSequence;

    const row_str = coords_str[0..semicolon_idx];
    const col_str = coords_str[semicolon_idx + 1 ..];

    const row = try std.fmt.parseInt(i16, row_str, 10);
    const col = try std.fmt.parseInt(i16, col_str, 10);

    // Convert from 1-indexed to 0-indexed
    return COORD{
        .X = col - 1,
        .Y = row - 1,
    };
}

// ============================================================================
// Keyboard Event Handling
// ============================================================================

pub const KeyEvent = struct {
    key_down: bool,
    virtual_key_code: u16,
    control_key_state: u32,
    unicode_char: u21,
};

pub const MouseEvent = struct {
    x: i16,
    y: i16,
    button_state: u32,
};

pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
};

pub fn isCtrlC(event: InputEvent) bool {
    if (event != .key) return false;
    const key = event.key;
    return key.virtual_key_code == VK_C and hasCtrlPressed(event);
}

pub fn isAltF4(event: InputEvent) bool {
    if (event != .key) return false;
    const key = event.key;
    return key.virtual_key_code == VK_F4 and hasAltPressed(event);
}

pub fn isKeyDown(event: InputEvent) bool {
    if (event != .key) return false;
    return event.key.key_down;
}

pub fn isKeyEvent(event: InputEvent) bool {
    return event == .key;
}

pub fn hasCtrlPressed(event: InputEvent) bool {
    if (event != .key) return false;
    const state = event.key.control_key_state;
    return (state & LEFT_CTRL_PRESSED) != 0 or (state & RIGHT_CTRL_PRESSED) != 0;
}

pub fn hasAltPressed(event: InputEvent) bool {
    if (event != .key) return false;
    const state = event.key.control_key_state;
    return (state & LEFT_ALT_PRESSED) != 0 or (state & RIGHT_ALT_PRESSED) != 0;
}

pub fn hasShiftPressed(event: InputEvent) bool {
    if (event != .key) return false;
    const state = event.key.control_key_state;
    return (state & SHIFT_PRESSED) != 0;
}

pub fn eventToUtf8(event: InputEvent) ![]const u8 {
    if (event != .key) return error.NotAKeyEvent;

    const char = event.key.unicode_char;

    // Convert Unicode codepoint to UTF-8
    var buf: [4]u8 = undefined;
    const len = try std.unicode.utf8Encode(char, &buf);

    // Return a static string slice (this is a simplified version)
    // In real code, you'd need to allocate or use a buffer
    return buf[0..len];
}

pub fn virtualKeyToString(vk: u16) []const u8 {
    return switch (vk) {
        // Arrow keys
        VK_LEFT => "Left",
        VK_UP => "Up",
        VK_RIGHT => "Right",
        VK_DOWN => "Down",

        // Function keys
        0x70 => "F1",
        0x71 => "F2",
        0x72 => "F3",
        0x73 => "F4",
        0x74 => "F5",
        0x75 => "F6",
        0x76 => "F7",
        0x77 => "F8",
        0x78 => "F9",
        0x79 => "F10",
        0x7A => "F11",
        0x7B => "F12",

        else => "Unknown",
    };
}

// ============================================================================
// UTF-16 Encoding
// ============================================================================

pub fn utf8ToUtf16Le(allocator: Allocator, utf8: []const u8) ![]u16 {
    if (utf8.len == 0) {
        return try allocator.alloc(u16, 0);
    }

    const size = utf8ToUtf16BufferSize(utf8);
    var buf = try allocator.alloc(u16, size);
    errdefer allocator.free(buf);

    var utf16_idx: usize = 0;
    var utf8_idx: usize = 0;

    while (utf8_idx < utf8.len) {
        const len = std.unicode.utf8ByteSequenceLength(utf8[utf8_idx]) catch return error.InvalidUtf8;
        const codepoint = std.unicode.utf8Decode(utf8[utf8_idx .. utf8_idx + len]) catch return error.InvalidUtf8;

        if (codepoint <= 0xFFFF) {
            // BMP character
            buf[utf16_idx] = @intCast(codepoint);
            utf16_idx += 1;
        } else {
            // Surrogate pair
            const adjusted = codepoint - 0x10000;
            const high = @as(u16, @intCast((adjusted >> 10) + 0xD800));
            const low = @as(u16, @intCast((adjusted & 0x3FF) + 0xDC00));
            buf[utf16_idx] = high;
            buf[utf16_idx + 1] = low;
            utf16_idx += 2;
        }

        utf8_idx += len;
    }

    return buf;
}

pub fn utf16LeToUtf8(allocator: Allocator, utf16: []const u16) ![]u8 {
    if (utf16.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    const size = utf16ToUtf8BufferSize(utf16);
    var buf = try allocator.alloc(u8, size);
    errdefer allocator.free(buf);

    var utf8_idx: usize = 0;
    var utf16_idx: usize = 0;

    while (utf16_idx < utf16.len) {
        const unit = utf16[utf16_idx];

        if (unit >= 0xD800 and unit <= 0xDBFF) {
            // High surrogate
            if (utf16_idx + 1 >= utf16.len) {
                allocator.free(buf);
                return error.InvalidUtf16;
            }

            const low = utf16[utf16_idx + 1];
            if (low < 0xDC00 or low > 0xDFFF) {
                allocator.free(buf);
                return error.InvalidUtf16;
            }

            // Decode surrogate pair
            const high = unit;
            const codepoint = 0x10000 + ((@as(u32, high) - 0xD800) << 10) + (@as(u32, low) - 0xDC00);
            const len = std.unicode.utf8Encode(@intCast(codepoint), buf[utf8_idx..]) catch {
                allocator.free(buf);
                return error.InvalidCodepoint;
            };
            utf8_idx += len;
            utf16_idx += 2;
        } else if (unit >= 0xDC00 and unit <= 0xDFFF) {
            // Lone low surrogate
            allocator.free(buf);
            return error.InvalidUtf16;
        } else {
            // BMP character
            const len = std.unicode.utf8Encode(unit, buf[utf8_idx..]) catch {
                allocator.free(buf);
                return error.InvalidCodepoint;
            };
            utf8_idx += len;
            utf16_idx += 1;
        }
    }

    return buf;
}

pub fn utf8ToUtf16BufferSize(utf8: []const u8) usize {
    var size: usize = 0;
    var idx: usize = 0;

    while (idx < utf8.len) {
        const len = std.unicode.utf8ByteSequenceLength(utf8[idx]) catch break;
        const codepoint = std.unicode.utf8Decode(utf8[idx .. idx + len]) catch break;

        if (codepoint > 0xFFFF) {
            size += 2; // Surrogate pair
        } else {
            size += 1; // BMP character
        }

        idx += len;
    }

    return size;
}

pub fn utf16ToUtf8BufferSize(utf16: []const u16) usize {
    var size: usize = 0;
    var idx: usize = 0;

    while (idx < utf16.len) {
        const unit = utf16[idx];

        if (unit >= 0xD800 and unit <= 0xDBFF) {
            // High surrogate - 4 bytes in UTF-8
            size += 4;
            idx += 2;
        } else if (unit >= 0xDC00 and unit <= 0xDFFF) {
            // Invalid lone low surrogate
            idx += 1;
        } else if (unit >= 0x0800) {
            // 3-byte UTF-8
            size += 3;
            idx += 1;
        } else if (unit >= 0x0080) {
            // 2-byte UTF-8
            size += 2;
            idx += 1;
        } else {
            // 1-byte UTF-8
            size += 1;
            idx += 1;
        }
    }

    return size;
}

// ============================================================================
// ANSI Parsing for Legacy Console
// ============================================================================

pub const AnsiSegment = struct {
    text: []const u8,
    attribute: u16,
};

pub fn parseAnsiSegments(allocator: Allocator, ansi_str: []const u8) !std.ArrayList(AnsiSegment) {
    var segments = std.ArrayList(AnsiSegment).init(allocator);
    errdefer segments.deinit();

    var idx: usize = 0;
    var current_attr: u16 = 0x0007; // Default white
    var text_start: usize = 0;

    while (idx < ansi_str.len) {
        if (ansi_str[idx] == '\x1b' and idx + 1 < ansi_str.len and ansi_str[idx + 1] == '[') {
            // Found escape sequence
            // Save any pending text
            if (idx > text_start) {
                try segments.append(.{
                    .text = ansi_str[text_start..idx],
                    .attribute = current_attr,
                });
            }

            // Find end of sequence
            var seq_end = idx + 2;
            while (seq_end < ansi_str.len and ansi_str[seq_end] != 'm') : (seq_end += 1) {}

            if (seq_end < ansi_str.len) {
                // Parse attribute
                const seq = ansi_str[idx .. seq_end + 1];
                current_attr = ansiToConsoleAttribute(seq) catch current_attr;
                idx = seq_end + 1;
                text_start = idx;
            } else {
                idx += 1;
            }
        } else {
            idx += 1;
        }
    }

    // Add remaining text
    if (text_start < ansi_str.len) {
        try segments.append(.{
            .text = ansi_str[text_start..],
            .attribute = current_attr,
        });
    }

    return segments;
}
