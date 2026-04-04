//! Terminal capability detection
//!
//! Detects terminal feature support at runtime without external queries.
//! Capabilities include:
//! - Truecolor (24-bit RGB)
//! - Mouse event protocols
//! - Clipboard (OSC 52)
//! - Bracketed paste
//! - Synchronized output
//! - Hyperlinks (OSC 8)
//! - Graphics protocols (Sixel, Kitty)
//!
//! Detection uses environment variables and terminal type detection.
//! Conservative defaults - features disabled unless known supported.

const std = @import("std");
const terminal_detect = @import("terminal_detect.zig");

/// Terminal feature capabilities
pub const Capabilities = struct {
    truecolor: bool,      // 24-bit RGB color support
    mouse: bool,          // Mouse event support (SGR mode)
    clipboard: bool,      // OSC 52 clipboard support
    bracketed_paste: bool, // Bracketed paste mode
    sync_output: bool,    // Synchronized output (BSU/ESU)
    hyperlinks: bool,     // OSC 8 hyperlink support
    sixel: bool,          // Sixel graphics protocol
    kitty_graphics: bool, // Kitty graphics protocol

    /// Detect capabilities from environment
    pub fn detect() Capabilities {
        return detectWith(std.posix.getenv);
    }

    /// Detect with custom environment getter (for testing)
    pub fn detectWith(getenv: fn([]const u8) ?[]const u8) Capabilities {
        // 1. Detect terminal type
        const term_info = terminal_detect.TerminalInfo.detectWith(getenv);

        // 2. Get base capabilities from terminal type
        var caps = detectFor(term_info.type);

        // 3. Override truecolor based on COLORTERM
        if (getenv("COLORTERM")) |colorterm| {
            if (colorterm.len > 0) {
                if (std.mem.eql(u8, colorterm, "truecolor") or
                    std.mem.eql(u8, colorterm, "24bit")) {
                    caps.truecolor = true;
                }
            }
        }

        return caps;
    }

    /// Detect with explicit terminal type (for testing)
    pub fn detectFor(terminal_type: terminal_detect.TerminalType) Capabilities {
        return switch (terminal_type) {
            .kitty => .{
                .truecolor = true,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = true,
                .hyperlinks = true,
                .sixel = false,
                .kitty_graphics = true,
            },
            .iterm2 => .{
                .truecolor = true,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = true,
                .hyperlinks = true,
                .sixel = false,
                .kitty_graphics = false,
            },
            .alacritty => .{
                .truecolor = true,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = false,
                .hyperlinks = true,
                .sixel = false,
                .kitty_graphics = false,
            },
            .wezterm => .{
                .truecolor = true,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = true,
                .hyperlinks = true,
                .sixel = false,
                .kitty_graphics = false,
            },
            .windows_terminal => .{
                .truecolor = true,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = false,
                .hyperlinks = true,
                .sixel = false,
                .kitty_graphics = false,
            },
            .gnome_terminal => .{
                .truecolor = true,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = false,
                .hyperlinks = true,
                .sixel = false,
                .kitty_graphics = false,
            },
            .konsole => .{
                .truecolor = true,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = false,
                .hyperlinks = true,
                .sixel = false,
                .kitty_graphics = false,
            },
            .xterm => .{
                .truecolor = false,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = false,
                .hyperlinks = false,
                .sixel = false,
                .kitty_graphics = false,
            },
            .xterm_256color => .{
                .truecolor = false,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = false,
                .hyperlinks = false,
                .sixel = false,
                .kitty_graphics = false,
            },
            .tmux => .{
                .truecolor = false,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = false,
                .hyperlinks = false,
                .sixel = false,
                .kitty_graphics = false,
            },
            .screen => .{
                .truecolor = false,
                .mouse = true,
                .clipboard = false,
                .bracketed_paste = true,
                .sync_output = false,
                .hyperlinks = false,
                .sixel = false,
                .kitty_graphics = false,
            },
            .foot => .{
                .truecolor = true,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = true,
                .hyperlinks = true,
                .sixel = false,
                .kitty_graphics = false,
            },
            .vscode => .{
                .truecolor = true,
                .mouse = true,
                .clipboard = true,
                .bracketed_paste = true,
                .sync_output = false,
                .hyperlinks = true,
                .sixel = false,
                .kitty_graphics = false,
            },
            .unknown => .{
                .truecolor = false,
                .mouse = false,
                .clipboard = false,
                .bracketed_paste = false,
                .sync_output = false,
                .hyperlinks = false,
                .sixel = false,
                .kitty_graphics = false,
            },
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

// ============================================================================
// Per-Terminal Capability Matrix Tests
// ============================================================================

test "Kitty terminal capabilities" {
    const caps = Capabilities.detectFor(.kitty);

    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(true, caps.sync_output);
    try std.testing.expectEqual(true, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel); // Kitty uses own protocol
    try std.testing.expectEqual(true, caps.kitty_graphics);
}

test "iTerm2 terminal capabilities" {
    const caps = Capabilities.detectFor(.iterm2);

    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(true, caps.sync_output);
    try std.testing.expectEqual(true, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "Alacritty terminal capabilities" {
    const caps = Capabilities.detectFor(.alacritty);

    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output); // Not supported
    try std.testing.expectEqual(true, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "WezTerm terminal capabilities" {
    const caps = Capabilities.detectFor(.wezterm);

    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(true, caps.sync_output);
    try std.testing.expectEqual(true, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "Windows Terminal capabilities" {
    const caps = Capabilities.detectFor(.windows_terminal);

    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(true, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "GNOME Terminal capabilities" {
    const caps = Capabilities.detectFor(.gnome_terminal);

    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(true, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "xterm terminal capabilities" {
    const caps = Capabilities.detectFor(.xterm);

    try std.testing.expectEqual(false, caps.truecolor); // No truecolor without COLORTERM
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(false, caps.hyperlinks); // Not widely supported
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "xterm-256color terminal capabilities" {
    const caps = Capabilities.detectFor(.xterm_256color);

    try std.testing.expectEqual(false, caps.truecolor); // 256 color, not truecolor
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(false, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "tmux capabilities" {
    const caps = Capabilities.detectFor(.tmux);

    try std.testing.expectEqual(false, caps.truecolor); // Without COLORTERM
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard); // Passthrough to underlying terminal
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(false, caps.hyperlinks); // Passthrough issues
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "screen capabilities" {
    const caps = Capabilities.detectFor(.screen);

    try std.testing.expectEqual(false, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(false, caps.clipboard); // Limited support
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(false, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "unknown terminal capabilities" {
    const caps = Capabilities.detectFor(.unknown);

    // Conservative defaults - all false unless proven
    try std.testing.expectEqual(false, caps.truecolor);
    try std.testing.expectEqual(false, caps.mouse);
    try std.testing.expectEqual(false, caps.clipboard);
    try std.testing.expectEqual(false, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(false, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "foot terminal capabilities" {
    const caps = Capabilities.detectFor(.foot);

    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(true, caps.sync_output); // foot supports BSU/ESU
    try std.testing.expectEqual(true, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel); // Conservative - can't reliably detect
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "Konsole terminal capabilities" {
    const caps = Capabilities.detectFor(.konsole);

    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(true, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "VS Code terminal capabilities" {
    const caps = Capabilities.detectFor(.vscode);

    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(true, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

// ============================================================================
// COLORTERM Environment Variable Tests
// ============================================================================

test "COLORTERM=truecolor enables truecolor" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "COLORTERM")) {
                return "truecolor";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // COLORTERM=truecolor should enable truecolor even for generic xterm
    try std.testing.expectEqual(true, caps.truecolor);
}

test "COLORTERM=24bit enables truecolor" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "COLORTERM")) {
                return "24bit";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    try std.testing.expectEqual(true, caps.truecolor);
}

test "no COLORTERM with 256color TERM - no truecolor" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // 256 color support != truecolor without COLORTERM
    try std.testing.expectEqual(false, caps.truecolor);
}

test "COLORTERM overrides terminal type for truecolor" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "COLORTERM")) {
                return "truecolor";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "screen"; // screen normally doesn't support truecolor
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // COLORTERM should override terminal type detection
    try std.testing.expectEqual(true, caps.truecolor);
}

// ============================================================================
// Fallback Behavior Tests
// ============================================================================

test "unknown terminal with COLORTERM gets truecolor" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "COLORTERM")) {
                return "truecolor";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "totally-unknown-terminal";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // COLORTERM should enable truecolor even for unknown terminals
    try std.testing.expectEqual(true, caps.truecolor);
    // But other features should remain conservative
    try std.testing.expectEqual(false, caps.mouse);
    try std.testing.expectEqual(false, caps.hyperlinks);
}

test "unknown terminal without COLORTERM - minimal capabilities" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "bogus-terminal";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // All capabilities should be false for unknown terminals
    try std.testing.expectEqual(false, caps.truecolor);
    try std.testing.expectEqual(false, caps.mouse);
    try std.testing.expectEqual(false, caps.clipboard);
    try std.testing.expectEqual(false, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(false, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "dumb terminal - all capabilities false" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "dumb";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    try std.testing.expectEqual(false, caps.truecolor);
    try std.testing.expectEqual(false, caps.mouse);
    try std.testing.expectEqual(false, caps.clipboard);
    try std.testing.expectEqual(false, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(false, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

// ============================================================================
// Feature Combination Tests
// ============================================================================

test "terminal with mouse but no truecolor" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // xterm has mouse but no truecolor without COLORTERM
    try std.testing.expectEqual(false, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
}

test "terminal with clipboard but no hyperlinks" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // xterm-256color has clipboard but not hyperlinks
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(false, caps.hyperlinks);
}

test "full-featured terminal - all capabilities true" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "KITTY_WINDOW_ID")) {
                return "1";
            }
            if (std.mem.eql(u8, key, "COLORTERM")) {
                return "truecolor";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // Kitty should have all capabilities except sixel
    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.bracketed_paste);
    try std.testing.expectEqual(true, caps.sync_output);
    try std.testing.expectEqual(true, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel); // Kitty uses own protocol
    try std.testing.expectEqual(true, caps.kitty_graphics);
}

// ============================================================================
// Integration with terminal_detect Tests
// ============================================================================

test "detectFor uses TerminalType correctly" {
    // Test that detectFor produces same results as detectWith for same terminal
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "KITTY_WINDOW_ID")) {
                return "1";
            }
            return null;
        }
    };

    const caps_with = Capabilities.detectWith(Ctx.getenv);
    const caps_for = Capabilities.detectFor(.kitty);

    try std.testing.expectEqual(caps_for.truecolor, caps_with.truecolor);
    try std.testing.expectEqual(caps_for.mouse, caps_with.mouse);
    try std.testing.expectEqual(caps_for.clipboard, caps_with.clipboard);
    try std.testing.expectEqual(caps_for.bracketed_paste, caps_with.bracketed_paste);
    try std.testing.expectEqual(caps_for.sync_output, caps_with.sync_output);
    try std.testing.expectEqual(caps_for.hyperlinks, caps_with.hyperlinks);
    try std.testing.expectEqual(caps_for.sixel, caps_with.sixel);
    try std.testing.expectEqual(caps_for.kitty_graphics, caps_with.kitty_graphics);
}

test "detect uses environment detection" {
    // Just verify it doesn't crash - actual env varies by test environment
    const caps = Capabilities.detect();

    // Should return valid boolean values
    _ = caps.truecolor;
    _ = caps.mouse;
    _ = caps.clipboard;
    _ = caps.bracketed_paste;
    _ = caps.sync_output;
    _ = caps.hyperlinks;
    _ = caps.sixel;
    _ = caps.kitty_graphics;
}

// ============================================================================
// Edge Cases and Error Conditions
// ============================================================================

test "empty COLORTERM value ignored" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "COLORTERM")) {
                return "";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // Empty COLORTERM should not enable truecolor
    try std.testing.expectEqual(false, caps.truecolor);
}

test "COLORTERM with invalid value ignored" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "COLORTERM")) {
                return "bogus-value";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // Invalid COLORTERM values should not enable truecolor
    try std.testing.expectEqual(false, caps.truecolor);
}

test "no environment variables returns minimal capabilities" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            _ = key;
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // With no env vars, should detect as unknown and return minimal caps
    try std.testing.expectEqual(false, caps.truecolor);
    try std.testing.expectEqual(false, caps.mouse);
    try std.testing.expectEqual(false, caps.clipboard);
    try std.testing.expectEqual(false, caps.bracketed_paste);
    try std.testing.expectEqual(false, caps.sync_output);
    try std.testing.expectEqual(false, caps.hyperlinks);
    try std.testing.expectEqual(false, caps.sixel);
    try std.testing.expectEqual(false, caps.kitty_graphics);
}

test "COLORTERM case sensitivity" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "COLORTERM")) {
                return "TrueColor"; // Mixed case
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // Should be case-insensitive or reject - conservative approach rejects
    try std.testing.expectEqual(false, caps.truecolor);
}

test "tmux with COLORTERM enables truecolor" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "COLORTERM")) {
                return "truecolor";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "tmux-256color";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // tmux with COLORTERM should enable truecolor
    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
}

test "detectFor does not require environment variables" {
    // detectFor should work purely from TerminalType without env access
    const caps_kitty = Capabilities.detectFor(.kitty);
    const caps_xterm = Capabilities.detectFor(.xterm);
    const caps_unknown = Capabilities.detectFor(.unknown);

    // Each should return consistent results
    try std.testing.expectEqual(true, caps_kitty.truecolor);
    try std.testing.expectEqual(false, caps_xterm.truecolor);
    try std.testing.expectEqual(false, caps_unknown.truecolor);
}

test "kitty with COLORTERM still reports truecolor" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "KITTY_WINDOW_ID")) {
                return "1";
            }
            if (std.mem.eql(u8, key, "COLORTERM")) {
                return "truecolor";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // Kitty should report truecolor from terminal type even if COLORTERM also set
    try std.testing.expectEqual(true, caps.truecolor);
}

test "Windows Terminal in WSL2" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "WT_SESSION")) {
                return "12345678-1234-1234-1234-123456789012";
            }
            if (std.mem.eql(u8, key, "COLORTERM")) {
                return "truecolor";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const caps = Capabilities.detectWith(Ctx.getenv);

    // Windows Terminal should be detected with full capabilities
    try std.testing.expectEqual(true, caps.truecolor);
    try std.testing.expectEqual(true, caps.mouse);
    try std.testing.expectEqual(true, caps.clipboard);
    try std.testing.expectEqual(true, caps.hyperlinks);
}
