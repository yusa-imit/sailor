//! Terminal quirks database
//!
//! Handles terminal emulator-specific bugs, workarounds, and compatibility issues.
//! Uses terminal detection to apply appropriate quirks automatically.
//!
//! Known quirks:
//! - Kitty: UTF-8 rendering issues with certain emoji
//! - iTerm2: OSC 52 clipboard requires base64 padding
//! - Alacritty: Synchronized output not fully supported before v0.13
//! - Windows Terminal: SGR mouse reporting has bugs in early versions
//! - tmux: Passthrough escapes needed for some protocols
//! - Konsole: Sixel support but with limitations
//!
//! Usage:
//! ```zig
//! const quirks = Quirks.detect();
//! if (quirks.clipboard_needs_padding) {
//!     // Add base64 padding for iTerm2
//! }
//! ```

const std = @import("std");
const terminal_detect = @import("../terminal_detect.zig");

/// Terminal quirks flags
pub const Quirks = struct {
    /// OSC 52 clipboard requires strict base64 padding (iTerm2)
    clipboard_needs_padding: bool,

    /// Synchronized output not supported or buggy (Alacritty < v0.13)
    broken_sync_output: bool,

    /// SGR mouse reporting has coordinate bugs (Windows Terminal < v1.12)
    broken_sgr_mouse: bool,

    /// Sixel protocol has rendering issues (Konsole)
    broken_sixel: bool,

    /// UTF-8 emoji rendering issues (Kitty < v0.26)
    broken_emoji_rendering: bool,

    /// tmux passthrough needed for OSC sequences
    needs_tmux_passthrough: bool,

    /// Hyperlinks not clickable despite OSC 8 support (GNOME Terminal < v3.38)
    broken_hyperlinks: bool,

    /// Truecolor requires explicit COLORTERM=truecolor (some xterm variants)
    needs_colorterm_hint: bool,

    /// Detect quirks from environment
    pub fn detect() Quirks {
        const builtin = @import("builtin");
        if (builtin.os.tag == .windows) {
            const Ctx = struct {
                threadlocal var buf: [4096]u8 = undefined;

                fn getenv(key: []const u8) ?[]const u8 {
                    var key_buf: [256]u16 = undefined;
                    if (key.len >= key_buf.len) return null;

                    var i: usize = 0;
                    while (i < key.len) : (i += 1) {
                        key_buf[i] = key[i];
                    }
                    key_buf[i] = 0;

                    const len = std.os.windows.kernel32.GetEnvironmentVariableW(
                        &key_buf,
                        @ptrCast(&buf),
                        buf.len / 2,
                    );

                    if (len == 0 or len >= buf.len / 2) return null;

                    const wide_slice = @as([*]const u16, @ptrCast(&buf))[0..len];
                    const utf8_len = std.unicode.utf16LeToUtf8(&buf, wide_slice) catch return null;

                    return buf[0..utf8_len];
                }
            };
            return detectWith(Ctx.getenv);
        } else {
            return detectWith(std.posix.getenv);
        }
    }

    /// Detect with custom environment getter (for testing)
    pub fn detectWith(getenv: fn([]const u8) ?[]const u8) Quirks {
        const term_info = terminal_detect.TerminalInfo.detectWith(getenv);
        return detectFor(term_info);
    }

    /// Detect quirks for specific terminal
    pub fn detectFor(term_info: terminal_detect.TerminalInfo) Quirks {
        var quirks = Quirks{
            .clipboard_needs_padding = false,
            .broken_sync_output = false,
            .broken_sgr_mouse = false,
            .broken_sixel = false,
            .broken_emoji_rendering = false,
            .needs_tmux_passthrough = false,
            .broken_hyperlinks = false,
            .needs_colorterm_hint = false,
        };

        switch (term_info.type) {
            .iterm2 => {
                // iTerm2 requires strict base64 padding for OSC 52 clipboard
                quirks.clipboard_needs_padding = true;
            },

            .alacritty => {
                // Alacritty < v0.13 has broken synchronized output
                if (term_info.version) |ver| {
                    if (compareVersion(ver, "0.13.0") < 0) {
                        quirks.broken_sync_output = true;
                    }
                } else {
                    // Unknown version — assume broken to be safe
                    quirks.broken_sync_output = true;
                }
            },

            .windows_terminal => {
                // Windows Terminal < v1.12 has SGR mouse coordinate bugs
                if (term_info.version) |ver| {
                    if (compareVersion(ver, "1.12.0") < 0) {
                        quirks.broken_sgr_mouse = true;
                    }
                }
            },

            .kitty => {
                // Kitty < v0.26 has emoji rendering issues
                if (term_info.version) |ver| {
                    if (compareVersion(ver, "0.26.0") < 0) {
                        quirks.broken_emoji_rendering = true;
                    }
                }
            },

            .konsole => {
                // Konsole's sixel support is incomplete
                quirks.broken_sixel = true;
            },

            .gnome_terminal => {
                // GNOME Terminal < v3.38 hyperlinks not clickable
                if (term_info.version) |ver| {
                    // VTE_VERSION is numeric (e.g., "6003" for 60.03)
                    if (parseVteVersion(ver)) |vte_ver| {
                        if (vte_ver < 6200) { // v3.38 → VTE 0.62
                            quirks.broken_hyperlinks = true;
                        }
                    }
                }
            },

            .tmux, .screen => {
                // tmux/screen need passthrough for OSC sequences
                quirks.needs_tmux_passthrough = true;
            },

            .xterm, .xterm_256color => {
                // Some xterm variants need COLORTERM hint for truecolor
                quirks.needs_colorterm_hint = true;
            },

            else => {
                // Unknown terminals — enable conservative workarounds
                quirks.needs_colorterm_hint = true;
            },
        }

        return quirks;
    }
};

/// Compare semantic versions (major.minor.patch)
/// Returns: -1 if a < b, 0 if a == b, 1 if a > b
fn compareVersion(a: []const u8, b: []const u8) i8 {
    const a_parts = parseVersionParts(a) orelse return -1;
    const b_parts = parseVersionParts(b) orelse return 1;

    if (a_parts[0] != b_parts[0]) return if (a_parts[0] < b_parts[0]) -1 else 1;
    if (a_parts[1] != b_parts[1]) return if (a_parts[1] < b_parts[1]) -1 else 1;
    if (a_parts[2] != b_parts[2]) return if (a_parts[2] < b_parts[2]) -1 else 1;

    return 0;
}

/// Parse version string "major.minor.patch" → [3]u32
fn parseVersionParts(ver: []const u8) ?[3]u32 {
    var parts: [3]u32 = .{ 0, 0, 0 };
    var it = std.mem.splitScalar(u8, ver, '.');
    var i: usize = 0;

    while (it.next()) |part| : (i += 1) {
        if (i >= 3) break; // Ignore extra parts
        parts[i] = std.fmt.parseInt(u32, part, 10) catch return null;
    }

    return parts;
}

/// Parse VTE version (numeric format like "6003" → 6003)
fn parseVteVersion(ver: []const u8) ?u32 {
    return std.fmt.parseInt(u32, ver, 10) catch null;
}

// ============================================================================
// Tests
// ============================================================================

test "Quirks - iTerm2 clipboard padding" {
    const getenv = struct {
        fn get(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) return "iTerm.app";
            return null;
        }
    }.get;

    const quirks = Quirks.detectWith(getenv);
    try std.testing.expect(quirks.clipboard_needs_padding);
    try std.testing.expect(!quirks.broken_sync_output);
}

test "Quirks - Alacritty old version sync output" {
    const getenv = struct {
        fn get(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "ALACRITTY_SOCKET")) return "/tmp/alacritty.sock";
            return null;
        }
    }.get;

    const quirks = Quirks.detectWith(getenv);
    try std.testing.expect(quirks.broken_sync_output); // Unknown version → assume broken
}

test "Quirks - Windows Terminal old version mouse" {
    const term_info = terminal_detect.TerminalInfo{
        .type = .windows_terminal,
        .name = "Windows Terminal",
        .version = "1.11.0",
    };

    const quirks = Quirks.detectFor(term_info);
    try std.testing.expect(quirks.broken_sgr_mouse);
}

test "Quirks - Windows Terminal new version mouse" {
    const term_info = terminal_detect.TerminalInfo{
        .type = .windows_terminal,
        .name = "Windows Terminal",
        .version = "1.12.0",
    };

    const quirks = Quirks.detectFor(term_info);
    try std.testing.expect(!quirks.broken_sgr_mouse);
}

test "Quirks - Kitty old version emoji" {
    const term_info = terminal_detect.TerminalInfo{
        .type = .kitty,
        .name = "Kitty",
        .version = "0.25.0",
    };

    const quirks = Quirks.detectFor(term_info);
    try std.testing.expect(quirks.broken_emoji_rendering);
}

test "Quirks - Kitty new version emoji" {
    const term_info = terminal_detect.TerminalInfo{
        .type = .kitty,
        .name = "Kitty",
        .version = "0.26.0",
    };

    const quirks = Quirks.detectFor(term_info);
    try std.testing.expect(!quirks.broken_emoji_rendering);
}

test "Quirks - Konsole sixel" {
    const term_info = terminal_detect.TerminalInfo{
        .type = .konsole,
        .name = "Konsole",
        .version = null,
    };

    const quirks = Quirks.detectFor(term_info);
    try std.testing.expect(quirks.broken_sixel);
}

test "Quirks - GNOME Terminal old VTE hyperlinks" {
    const term_info = terminal_detect.TerminalInfo{
        .type = .gnome_terminal,
        .name = "GNOME Terminal",
        .version = "6100", // VTE 0.61 < 0.62
    };

    const quirks = Quirks.detectFor(term_info);
    try std.testing.expect(quirks.broken_hyperlinks);
}

test "Quirks - GNOME Terminal new VTE hyperlinks" {
    const term_info = terminal_detect.TerminalInfo{
        .type = .gnome_terminal,
        .name = "GNOME Terminal",
        .version = "6200", // VTE 0.62
    };

    const quirks = Quirks.detectFor(term_info);
    try std.testing.expect(!quirks.broken_hyperlinks);
}

test "Quirks - tmux passthrough" {
    const term_info = terminal_detect.TerminalInfo{
        .type = .tmux,
        .name = "tmux",
        .version = null,
    };

    const quirks = Quirks.detectFor(term_info);
    try std.testing.expect(quirks.needs_tmux_passthrough);
}

test "Quirks - screen passthrough" {
    const term_info = terminal_detect.TerminalInfo{
        .type = .screen,
        .name = "screen",
        .version = null,
    };

    const quirks = Quirks.detectFor(term_info);
    try std.testing.expect(quirks.needs_tmux_passthrough);
}

test "Quirks - xterm colorterm hint" {
    const term_info = terminal_detect.TerminalInfo{
        .type = .xterm,
        .name = "xterm",
        .version = null,
    };

    const quirks = Quirks.detectFor(term_info);
    try std.testing.expect(quirks.needs_colorterm_hint);
}

test "Quirks - unknown terminal conservative defaults" {
    const term_info = terminal_detect.TerminalInfo{
        .type = .unknown,
        .name = "unknown",
        .version = null,
    };

    const quirks = Quirks.detectFor(term_info);
    try std.testing.expect(quirks.needs_colorterm_hint); // Conservative default
}

test "compareVersion - equal" {
    try std.testing.expectEqual(@as(i8, 0), compareVersion("1.2.3", "1.2.3"));
}

test "compareVersion - major less" {
    try std.testing.expectEqual(@as(i8, -1), compareVersion("1.2.3", "2.0.0"));
}

test "compareVersion - major greater" {
    try std.testing.expectEqual(@as(i8, 1), compareVersion("2.0.0", "1.9.9"));
}

test "compareVersion - minor less" {
    try std.testing.expectEqual(@as(i8, -1), compareVersion("1.2.3", "1.3.0"));
}

test "compareVersion - minor greater" {
    try std.testing.expectEqual(@as(i8, 1), compareVersion("1.3.0", "1.2.9"));
}

test "compareVersion - patch less" {
    try std.testing.expectEqual(@as(i8, -1), compareVersion("1.2.3", "1.2.4"));
}

test "compareVersion - patch greater" {
    try std.testing.expectEqual(@as(i8, 1), compareVersion("1.2.4", "1.2.3"));
}

test "parseVersionParts - valid" {
    const parts = parseVersionParts("1.2.3");
    try std.testing.expect(parts != null);
    try std.testing.expectEqual(@as(u32, 1), parts.?[0]);
    try std.testing.expectEqual(@as(u32, 2), parts.?[1]);
    try std.testing.expectEqual(@as(u32, 3), parts.?[2]);
}

test "parseVersionParts - two parts" {
    const parts = parseVersionParts("1.2");
    try std.testing.expect(parts != null);
    try std.testing.expectEqual(@as(u32, 1), parts.?[0]);
    try std.testing.expectEqual(@as(u32, 2), parts.?[1]);
    try std.testing.expectEqual(@as(u32, 0), parts.?[2]); // Default to 0
}

test "parseVersionParts - invalid" {
    const parts = parseVersionParts("1.x.3");
    try std.testing.expect(parts == null);
}

test "parseVteVersion - valid" {
    const ver = parseVteVersion("6200");
    try std.testing.expect(ver != null);
    try std.testing.expectEqual(@as(u32, 6200), ver.?);
}

test "parseVteVersion - invalid" {
    const ver = parseVteVersion("invalid");
    try std.testing.expect(ver == null);
}
