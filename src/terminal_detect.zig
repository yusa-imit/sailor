//! Terminal emulator detection
//!
//! Detects terminal emulator type from environment variables for feature-specific optimizations.
//! Supports:
//! - Major terminal emulators (Kitty, iTerm2, WezTerm, Alacritty, etc.)
//! - Multiplexers (tmux, screen)
//! - Generic xterm compatibility
//! - Version detection where available
//!
//! Detection uses environment variables only — no external dependencies.

const std = @import("std");

/// Terminal emulator type
pub const TerminalType = enum {
    xterm,           // Generic xterm
    xterm_256color,  // xterm with 256 colors
    kitty,           // Kitty terminal
    iterm2,          // iTerm2 (macOS)
    windows_terminal, // Windows Terminal
    alacritty,       // Alacritty
    wezterm,         // WezTerm
    foot,            // Foot (Wayland)
    gnome_terminal,  // GNOME Terminal
    konsole,         // KDE Konsole
    tmux,            // tmux multiplexer
    screen,          // GNU screen
    vscode,          // VS Code integrated terminal
    unknown,         // Cannot detect or unrecognized
};

/// Terminal information
pub const TerminalInfo = struct {
    type: TerminalType,
    name: []const u8,        // e.g., "kitty", "iTerm2"
    version: ?[]const u8,    // Version string if detectable

    /// Detect terminal emulator from environment variables
    pub fn detect() TerminalInfo {
        return detectWith(std.posix.getenv);
    }

    /// Detect with custom environment getter (for testing)
    pub fn detectWith(getenv: fn([]const u8) ?[]const u8) TerminalInfo {
        // Detection priority: most specific → most generic

        // 1. Check WT_SESSION (Windows Terminal)
        if (getenv("WT_SESSION")) |wt| {
            if (wt.len > 0) {
                return .{
                    .type = .windows_terminal,
                    .name = "Windows Terminal",
                    .version = null,
                };
            }
        }

        // 2. Check KITTY_WINDOW_ID (Kitty)
        if (getenv("KITTY_WINDOW_ID")) |_| {
            return .{
                .type = .kitty,
                .name = "Kitty",
                .version = null,
            };
        }

        // 3. Check ALACRITTY_SOCKET or ALACRITTY_LOG (Alacritty)
        if (getenv("ALACRITTY_SOCKET")) |_| {
            return .{
                .type = .alacritty,
                .name = "Alacritty",
                .version = null,
            };
        }
        if (getenv("ALACRITTY_LOG")) |_| {
            return .{
                .type = .alacritty,
                .name = "Alacritty",
                .version = null,
            };
        }

        // 4. Check KONSOLE_VERSION (KDE Konsole) — before VTE_VERSION
        if (getenv("KONSOLE_VERSION")) |ver| {
            if (ver.len > 0) {
                return .{
                    .type = .konsole,
                    .name = "Konsole",
                    .version = ver,
                };
            }
        }

        // 5. Check VTE_VERSION (GNOME Terminal)
        if (getenv("VTE_VERSION")) |vte| {
            if (vte.len > 0) {
                return .{
                    .type = .gnome_terminal,
                    .name = "GNOME Terminal",
                    .version = vte,
                };
            }
        }

        // 6. Check TERM_PROGRAM (iTerm2, WezTerm, VS Code, etc.)
        if (getenv("TERM_PROGRAM")) |prog| {
            const version = blk: {
                if (getenv("TERM_PROGRAM_VERSION")) |v| {
                    if (v.len > 0) {
                        break :blk v;
                    }
                }
                break :blk null;
            };

            if (std.mem.eql(u8, prog, "iTerm.app")) {
                return .{
                    .type = .iterm2,
                    .name = "iTerm2",
                    .version = version,
                };
            }
            if (std.mem.eql(u8, prog, "WezTerm")) {
                return .{
                    .type = .wezterm,
                    .name = "WezTerm",
                    .version = version,
                };
            }
            if (std.mem.eql(u8, prog, "vscode")) {
                return .{
                    .type = .vscode,
                    .name = "VS Code",
                    .version = version,
                };
            }
        }

        // 7. Parse TERM variable
        if (getenv("TERM")) |term| {
            if (term.len == 0) {
                return .{
                    .type = .unknown,
                    .name = "unknown",
                    .version = null,
                };
            }

            // tmux prefix
            if (std.mem.startsWith(u8, term, "tmux")) {
                return .{
                    .type = .tmux,
                    .name = "tmux",
                    .version = null,
                };
            }

            // screen prefix
            if (std.mem.startsWith(u8, term, "screen")) {
                return .{
                    .type = .screen,
                    .name = "screen",
                    .version = null,
                };
            }

            // Exact matches
            if (std.mem.eql(u8, term, "foot")) {
                return .{
                    .type = .foot,
                    .name = "Foot",
                    .version = null,
                };
            }
            if (std.mem.eql(u8, term, "xterm-256color")) {
                return .{
                    .type = .xterm_256color,
                    .name = "xterm-256color",
                    .version = null,
                };
            }
            if (std.mem.eql(u8, term, "xterm-kitty")) {
                // Without KITTY_WINDOW_ID, treat as xterm variant
                return .{
                    .type = .xterm_256color,
                    .name = "xterm-256color",
                    .version = null,
                };
            }
            if (std.mem.eql(u8, term, "xterm")) {
                return .{
                    .type = .xterm,
                    .name = "xterm",
                    .version = null,
                };
            }
        }

        // 8. Fallback to unknown
        return .{
            .type = .unknown,
            .name = "unknown",
            .version = null,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

// Test helper: mock environment
const MockEnv = struct {
    vars: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) MockEnv {
        return .{
            .vars = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *MockEnv) void {
        self.vars.deinit();
    }

    fn set(self: *MockEnv, key: []const u8, value: []const u8) !void {
        try self.vars.put(key, value);
    }

    fn getenv(self: *const MockEnv, key: []const u8) ?[]const u8 {
        return self.vars.get(key);
    }
};

// ============================================================================
// Environment Variable Detection Tests
// ============================================================================

test "detect iTerm2 from TERM_PROGRAM" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
                return "iTerm.app";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.iterm2, info.type);
    try std.testing.expectEqualStrings("iTerm2", info.name);
}

test "detect WezTerm from TERM_PROGRAM" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
                return "WezTerm";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.wezterm, info.type);
    try std.testing.expectEqualStrings("WezTerm", info.name);
}

test "detect VS Code from TERM_PROGRAM" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
                return "vscode";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.vscode, info.type);
    try std.testing.expectEqualStrings("VS Code", info.name);
}

test "detect Windows Terminal from WT_SESSION" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "WT_SESSION")) {
                return "12345678-1234-1234-1234-123456789012";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.windows_terminal, info.type);
    try std.testing.expectEqualStrings("Windows Terminal", info.name);
}

test "detect Kitty from KITTY_WINDOW_ID" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "KITTY_WINDOW_ID")) {
                return "1";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.kitty, info.type);
    try std.testing.expectEqualStrings("Kitty", info.name);
}

test "detect Alacritty from ALACRITTY_SOCKET" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "ALACRITTY_SOCKET")) {
                return "/tmp/alacritty.sock";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.alacritty, info.type);
    try std.testing.expectEqualStrings("Alacritty", info.name);
}

test "detect xterm-256color from TERM" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.xterm_256color, info.type);
    try std.testing.expectEqualStrings("xterm-256color", info.name);
}

test "detect tmux from TERM prefix" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "tmux-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.tmux, info.type);
    try std.testing.expectEqualStrings("tmux", info.name);
}

test "detect screen from TERM prefix" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "screen-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.screen, info.type);
    try std.testing.expectEqualStrings("screen", info.name);
}

test "detect Foot from TERM" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "foot";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.foot, info.type);
    try std.testing.expectEqualStrings("Foot", info.name);
}

test "detect GNOME Terminal from VTE_VERSION" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "VTE_VERSION")) {
                return "7200";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.gnome_terminal, info.type);
    try std.testing.expectEqualStrings("GNOME Terminal", info.name);
}

test "detect Konsole from KONSOLE_VERSION" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "KONSOLE_VERSION")) {
                return "230600";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.konsole, info.type);
    try std.testing.expectEqualStrings("Konsole", info.name);
}

// ============================================================================
// Precedence Tests
// ============================================================================

test "TERM_PROGRAM takes precedence over TERM" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
                return "iTerm.app";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.iterm2, info.type);
}

test "WT_SESSION takes precedence over TERM" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "WT_SESSION")) {
                return "guid";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.windows_terminal, info.type);
}

test "KITTY_WINDOW_ID takes precedence over TERM" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "KITTY_WINDOW_ID")) {
                return "1";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-kitty";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.kitty, info.type);
}

test "VTE_VERSION takes precedence over generic TERM" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "VTE_VERSION")) {
                return "7200";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.gnome_terminal, info.type);
}

test "tmux TERM prefix overrides generic xterm" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "tmux-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.tmux, info.type);
}

// ============================================================================
// Fallback Behavior Tests
// ============================================================================

test "no env vars returns unknown" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            _ = key;
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.unknown, info.type);
    try std.testing.expectEqualStrings("unknown", info.name);
    try std.testing.expectEqual(@as(?[]const u8, null), info.version);
}

test "empty TERM returns unknown" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.unknown, info.type);
}

test "unrecognized TERM returns unknown" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "bogus-terminal";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.unknown, info.type);
}

test "dumb terminal returns unknown" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "dumb";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.unknown, info.type);
}

test "generic xterm from TERM" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.xterm, info.type);
    try std.testing.expectEqualStrings("xterm", info.name);
}

// ============================================================================
// Version Detection Tests
// ============================================================================

test "iTerm2 version from TERM_PROGRAM_VERSION" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
                return "iTerm.app";
            }
            if (std.mem.eql(u8, key, "TERM_PROGRAM_VERSION")) {
                return "3.4.19";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.iterm2, info.type);
    try std.testing.expect(info.version != null);
    try std.testing.expectEqualStrings("3.4.19", info.version.?);
}

test "WezTerm version from TERM_PROGRAM_VERSION" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
                return "WezTerm";
            }
            if (std.mem.eql(u8, key, "TERM_PROGRAM_VERSION")) {
                return "20230408-112425-69ae8472";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.wezterm, info.type);
    try std.testing.expect(info.version != null);
    try std.testing.expectEqualStrings("20230408-112425-69ae8472", info.version.?);
}

test "GNOME Terminal version from VTE_VERSION" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "VTE_VERSION")) {
                return "7200";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.gnome_terminal, info.type);
    try std.testing.expect(info.version != null);
    try std.testing.expectEqualStrings("7200", info.version.?);
}

test "Konsole version from KONSOLE_VERSION" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "KONSOLE_VERSION")) {
                return "230600";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.konsole, info.type);
    try std.testing.expect(info.version != null);
    try std.testing.expectEqualStrings("230600", info.version.?);
}

test "version is null when TERM_PROGRAM_VERSION not set" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
                return "iTerm.app";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.iterm2, info.type);
    try std.testing.expectEqual(@as(?[]const u8, null), info.version);
}

test "Kitty without version detection" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "KITTY_WINDOW_ID")) {
                return "1";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.kitty, info.type);
    try std.testing.expectEqual(@as(?[]const u8, null), info.version);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "multiple conflicting env vars - specific wins" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "KITTY_WINDOW_ID")) {
                return "1";
            }
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
                return "iTerm.app";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    // KITTY_WINDOW_ID is most specific, should win
    try std.testing.expectEqual(TerminalType.kitty, info.type);
}

test "very long env var value does not crash" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "x" ** 2048; // Very long value
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    // Should handle gracefully, return unknown
    try std.testing.expectEqual(TerminalType.unknown, info.type);
}

test "malformed version string handled gracefully" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
                return "iTerm.app";
            }
            if (std.mem.eql(u8, key, "TERM_PROGRAM_VERSION")) {
                return "not-a-version\x00\x01\x02";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.iterm2, info.type);
    // Version should be returned as-is (no validation required)
    try std.testing.expect(info.version != null);
}

test "empty version string treated as null" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
                return "iTerm.app";
            }
            if (std.mem.eql(u8, key, "TERM_PROGRAM_VERSION")) {
                return "";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.iterm2, info.type);
    try std.testing.expectEqual(@as(?[]const u8, null), info.version);
}

test "xterm-kitty variant detected as xterm-256color" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-kitty";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    // Without KITTY_WINDOW_ID, should detect as xterm variant
    try std.testing.expectEqual(TerminalType.xterm_256color, info.type);
}

test "case sensitivity in TERM_PROGRAM" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
                return "iterm.app"; // lowercase
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    // Should not match - case sensitive
    try std.testing.expectEqual(TerminalType.unknown, info.type);
}

test "screen with color depth suffix" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "TERM")) {
                return "screen.xterm-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    try std.testing.expectEqual(TerminalType.screen, info.type);
}

test "both KONSOLE_VERSION and VTE_VERSION - KONSOLE wins" {
    const Ctx = struct {
        fn getenv(key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "KONSOLE_VERSION")) {
                return "230600";
            }
            if (std.mem.eql(u8, key, "VTE_VERSION")) {
                return "7200";
            }
            if (std.mem.eql(u8, key, "TERM")) {
                return "xterm-256color";
            }
            return null;
        }
    };

    const info = TerminalInfo.detectWith(Ctx.getenv);

    // KONSOLE_VERSION should take precedence
    try std.testing.expectEqual(TerminalType.konsole, info.type);
}

// ============================================================================
// Real Environment Test
// ============================================================================

test "detect from real environment does not crash" {
    const info = TerminalInfo.detect();

    // Should always return something (at least unknown)
    try std.testing.expect(info.type == .unknown or
                          info.type == .xterm or
                          info.type == .xterm_256color or
                          info.type == .kitty or
                          info.type == .iterm2 or
                          info.type == .windows_terminal or
                          info.type == .alacritty or
                          info.type == .wezterm or
                          info.type == .foot or
                          info.type == .gnome_terminal or
                          info.type == .konsole or
                          info.type == .tmux or
                          info.type == .screen or
                          info.type == .vscode);

    // Name should not be empty
    try std.testing.expect(info.name.len > 0);
}
