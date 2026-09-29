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
    xterm, // Generic xterm
    xterm_256color, // xterm with 256 colors
    kitty, // Kitty terminal
    iterm2, // iTerm2 (macOS)
    windows_terminal, // Windows Terminal
    alacritty, // Alacritty
    wezterm, // WezTerm
    foot, // Foot (Wayland)
    gnome_terminal, // GNOME Terminal
    konsole, // KDE Konsole
    tmux, // tmux multiplexer
    screen, // GNU screen
    vscode, // VS Code integrated terminal
    unknown, // Cannot detect or unrecognized
};

/// Terminal information
pub const TerminalInfo = struct {
    type: TerminalType,
    name: []const u8, // e.g., "kitty", "iTerm2"
    version: ?[]const u8, // Version string if detectable

    /// Detect terminal emulator from environment variables.
    /// `environ_map` supplies TERM/TERM_PROGRAM/... (borrowed; the returned
    /// `version` slice may point into the map, so the map must outlive it).
    pub fn detect(environ_map: *const std.process.Environ.Map) TerminalInfo {
        // Precondition: the map is a live, addressable value.
        std.debug.assert(@intFromPtr(environ_map) != 0);
        const info = detectImpl(environ_map, mapGet);
        // Postcondition: a detected terminal always has a non-empty name.
        std.debug.assert(info.name.len > 0);
        return info;
    }

    fn mapGet(environ_map: *const std.process.Environ.Map, key: []const u8) ?[]const u8 {
        std.debug.assert(key.len > 0);
        return environ_map.get(key);
    }

    /// Detect with custom environment getter (for testing)
    pub fn detectWith(comptime getenv: fn ([]const u8) ?[]const u8) TerminalInfo {
        const Adapter = struct {
            fn get(_: void, key: []const u8) ?[]const u8 {
                std.debug.assert(key.len > 0);
                return getenv(key);
            }
        };
        return detectImpl({}, Adapter.get);
    }

    /// Shared detection body; `getFn(ctx, key)` looks up one environment variable.
    fn detectImpl(ctx: anytype, comptime getFn: anytype) TerminalInfo {
        // Detection priority: most specific → most generic
        if (fromEmulatorVars(
            getFn(ctx, "WT_SESSION"),
            getFn(ctx, "KITTY_WINDOW_ID"),
            getFn(ctx, "ALACRITTY_SOCKET"),
            getFn(ctx, "ALACRITTY_LOG"),
            getFn(ctx, "KONSOLE_VERSION"),
            getFn(ctx, "VTE_VERSION"),
        )) |info| return info;

        if (fromTermProgram(
            getFn(ctx, "TERM_PROGRAM"),
            getFn(ctx, "TERM_PROGRAM_VERSION"),
        )) |info| return info;

        if (fromTerm(getFn(ctx, "TERM"))) |info| return info;

        // 8. Fallback to unknown
        return .{ .type = .unknown, .name = "unknown", .version = null };
    }

    /// Steps 1-5: emulator-specific variables, already resolved by the caller.
    fn fromEmulatorVars(
        wt_session: ?[]const u8,
        kitty_window_id: ?[]const u8,
        alacritty_socket: ?[]const u8,
        alacritty_log: ?[]const u8,
        konsole_version: ?[]const u8,
        vte_version: ?[]const u8,
    ) ?TerminalInfo {
        // Windows Terminal: WT_SESSION must be non-empty.
        if (wt_session) |wt| {
            if (wt.len > 0) {
                return .{ .type = .windows_terminal, .name = "Windows Terminal", .version = null };
            }
        }
        // Kitty: KITTY_WINDOW_ID present (any value).
        if (kitty_window_id != null) {
            return .{ .type = .kitty, .name = "Kitty", .version = null };
        }
        // Alacritty: ALACRITTY_SOCKET or ALACRITTY_LOG present.
        if (alacritty_socket != null or alacritty_log != null) {
            return .{ .type = .alacritty, .name = "Alacritty", .version = null };
        }
        // KDE Konsole — checked before VTE_VERSION.
        if (konsole_version) |ver| {
            if (ver.len > 0) return .{ .type = .konsole, .name = "Konsole", .version = ver };
        }
        // GNOME Terminal (VTE).
        if (vte_version) |vte| {
            if (vte.len > 0) {
                return .{ .type = .gnome_terminal, .name = "GNOME Terminal", .version = vte };
            }
        }
        return null;
    }

    /// Step 6: TERM_PROGRAM (iTerm2, WezTerm, VS Code); null when unset or unrecognized.
    fn fromTermProgram(prog_opt: ?[]const u8, version_raw: ?[]const u8) ?TerminalInfo {
        const prog = prog_opt orelse return null;
        var version: ?[]const u8 = null;
        if (version_raw) |v| {
            if (v.len > 0) version = v;
        }
        // Negative space: an empty/absent version is never reported as a version.
        std.debug.assert(version == null or version.?.len > 0);

        if (std.mem.eql(u8, prog, "iTerm.app")) {
            return .{ .type = .iterm2, .name = "iTerm2", .version = version };
        }
        if (std.mem.eql(u8, prog, "WezTerm")) {
            return .{ .type = .wezterm, .name = "WezTerm", .version = version };
        }
        if (std.mem.eql(u8, prog, "vscode")) {
            return .{ .type = .vscode, .name = "VS Code", .version = version };
        }
        return null;
    }

    /// Step 7: parse the TERM variable; null when unset or unrecognized.
    fn fromTerm(term_opt: ?[]const u8) ?TerminalInfo {
        const term = term_opt orelse return null;
        if (term.len == 0) return .{ .type = .unknown, .name = "unknown", .version = null };
        // Positive space: only non-empty values reach the prefix/exact matching below.
        std.debug.assert(term.len > 0);

        if (std.mem.startsWith(u8, term, "tmux")) {
            return .{ .type = .tmux, .name = "tmux", .version = null };
        }
        if (std.mem.startsWith(u8, term, "screen")) {
            return .{ .type = .screen, .name = "screen", .version = null };
        }
        if (std.mem.eql(u8, term, "foot")) {
            return .{ .type = .foot, .name = "Foot", .version = null };
        }
        if (std.mem.eql(u8, term, "xterm-256color")) {
            return .{ .type = .xterm_256color, .name = "xterm-256color", .version = null };
        }
        // Without KITTY_WINDOW_ID, xterm-kitty is treated as an xterm variant.
        if (std.mem.eql(u8, term, "xterm-kitty")) {
            return .{ .type = .xterm_256color, .name = "xterm-256color", .version = null };
        }
        if (std.mem.eql(u8, term, "xterm")) {
            return .{ .type = .xterm, .name = "xterm", .version = null };
        }
        return null;
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
    var environ_map = try std.testing.environ.createMap(std.testing.allocator);
    defer environ_map.deinit();

    const info = TerminalInfo.detect(&environ_map);

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

test "detect from injected environ map" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();
    try environ_map.put("KITTY_WINDOW_ID", "1");

    const info = TerminalInfo.detect(&environ_map);
    try std.testing.expectEqual(TerminalType.kitty, info.type);
}

test "detect from empty environ map is unknown" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    const info = TerminalInfo.detect(&environ_map);
    try std.testing.expectEqual(TerminalType.unknown, info.type);
}
