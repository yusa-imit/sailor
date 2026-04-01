//! Debug Logging System — Conditional debug output (env-based)
//!
//! Provides structured debug logging controlled by environment variables:
//! - SAILOR_DEBUG=1 - Enable all debug output
//! - SAILOR_DEBUG=module - Enable debug for specific module (e.g., "tui", "arg", "repl")
//! - SAILOR_DEBUG=module:level - Enable with specific level (trace, debug, info, warn, error)
//!
//! Example usage:
//! ```zig
//! const log = @import("debug_log.zig");
//! const debug = log.scoped(.tui);
//!
//! debug.trace("Rendering frame {d}", .{frame_count});
//! debug.info("Terminal size: {d}x{d}", .{cols, rows});
//! debug.warn("Widget exceeded bounds: {s}", .{widget_name});
//! debug.err("Failed to render widget: {s}", .{@errorName(e)});
//! ```

const std = @import("std");
const builtin = @import("builtin");

/// Log levels (ordered by severity)
pub const Level = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,

    /// Parse level from string
    pub fn parse(str: []const u8) ?Level {
        if (std.mem.eql(u8, str, "trace")) return .trace;
        if (std.mem.eql(u8, str, "debug")) return .debug;
        if (std.mem.eql(u8, str, "info")) return .info;
        if (std.mem.eql(u8, str, "warn")) return .warn;
        if (std.mem.eql(u8, str, "error") or std.mem.eql(u8, str, "err")) return .err;
        return null;
    }

    /// Get ANSI color for level
    pub fn color(self: Level) []const u8 {
        return switch (self) {
            .trace => "\x1b[90m", // dark gray
            .debug => "\x1b[36m", // cyan
            .info => "\x1b[32m", // green
            .warn => "\x1b[33m", // yellow
            .err => "\x1b[31m", // red
        };
    }

    /// Get short name for level
    pub fn shortName(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO ",
            .warn => "WARN ",
            .err => "ERROR",
        };
    }
};

/// Module scope for debug logging
pub const Scope = enum {
    sailor, // general
    term,
    color,
    arg,
    repl,
    progress,
    fmt,
    tui,
    widgets,
    layout,
    buffer,
    events,
    sixel,
    kitty,
    env,
};

/// Global debug configuration (read from env vars)
var global_enabled: bool = false;
var global_scope: ?Scope = null;
var global_level: Level = .debug;
var init_done: bool = false;

/// Initialize debug logging from environment
fn initOnce() void {
    if (init_done) return;
    init_done = true;

    const env_debug = std.process.getEnvVarOwned(
        std.heap.page_allocator,
        "SAILOR_DEBUG",
    ) catch return;
    defer std.heap.page_allocator.free(env_debug);

    if (env_debug.len == 0) return;

    // SAILOR_DEBUG=1 - enable all
    if (std.mem.eql(u8, env_debug, "1")) {
        global_enabled = true;
        return;
    }

    // SAILOR_DEBUG=module:level
    if (std.mem.indexOf(u8, env_debug, ":")) |colon_idx| {
        const scope_str = env_debug[0..colon_idx];
        const level_str = env_debug[colon_idx + 1 ..];

        global_scope = parseScopeName(scope_str);
        global_level = Level.parse(level_str) orelse .debug;
        global_enabled = global_scope != null;
    } else {
        // SAILOR_DEBUG=module
        global_scope = parseScopeName(env_debug);
        global_enabled = global_scope != null;
    }
}

/// Parse scope from string
fn parseScopeName(name: []const u8) ?Scope {
    inline for (@typeInfo(Scope).@"enum".fields) |field| {
        if (std.mem.eql(u8, name, field.name)) {
            return @enumFromInt(field.value);
        }
    }
    return null;
}

/// Check if logging is enabled for scope and level
fn isEnabled(scope: Scope, level: Level) bool {
    if (!init_done) initOnce();
    if (!global_enabled) return false;

    // If global scope is set, only log for that scope
    if (global_scope) |s| {
        if (s != scope) return false;
    }

    // Check level threshold
    return @intFromEnum(level) >= @intFromEnum(global_level);
}

/// Scoped logger
pub fn scoped(comptime scope: Scope) type {
    return struct {
        /// Log at TRACE level
        pub fn trace(comptime fmt: []const u8, args: anytype) void {
            logImpl(scope, .trace, fmt, args);
        }

        /// Log at DEBUG level
        pub fn debug(comptime fmt: []const u8, args: anytype) void {
            logImpl(scope, .debug, fmt, args);
        }

        /// Log at INFO level
        pub fn info(comptime fmt: []const u8, args: anytype) void {
            logImpl(scope, .info, fmt, args);
        }

        /// Log at WARN level
        pub fn warn(comptime fmt: []const u8, args: anytype) void {
            logImpl(scope, .warn, fmt, args);
        }

        /// Log at ERROR level
        pub fn err(comptime fmt: []const u8, args: anytype) void {
            logImpl(scope, .err, fmt, args);
        }
    };
}

/// Internal logging implementation
fn logImpl(scope: Scope, level: Level, comptime fmt: []const u8, args: anytype) void {
    if (!isEnabled(scope, level)) return;

    const scope_name = @tagName(scope);

    // Format: [LEVEL] scope: message
    // Use std.debug.print which writes to stderr
    std.debug.print("{s}[{s}]\x1b[0m {s}: ", .{
        level.color(),
        level.shortName(),
        scope_name,
    });

    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

// ============================================================================
// Tests
// ============================================================================

test "Level.parse" {
    try std.testing.expectEqual(Level.trace, Level.parse("trace").?);
    try std.testing.expectEqual(Level.debug, Level.parse("debug").?);
    try std.testing.expectEqual(Level.info, Level.parse("info").?);
    try std.testing.expectEqual(Level.warn, Level.parse("warn").?);
    try std.testing.expectEqual(Level.err, Level.parse("error").?);
    try std.testing.expectEqual(Level.err, Level.parse("err").?);
    try std.testing.expectEqual(@as(?Level, null), Level.parse("invalid"));
}

test "Level.shortName" {
    try std.testing.expectEqualStrings("TRACE", Level.trace.shortName());
    try std.testing.expectEqualStrings("DEBUG", Level.debug.shortName());
    try std.testing.expectEqualStrings("INFO ", Level.info.shortName());
    try std.testing.expectEqualStrings("WARN ", Level.warn.shortName());
    try std.testing.expectEqualStrings("ERROR", Level.err.shortName());
}

test "parseScopeName" {
    try std.testing.expectEqual(Scope.sailor, parseScopeName("sailor").?);
    try std.testing.expectEqual(Scope.tui, parseScopeName("tui").?);
    try std.testing.expectEqual(Scope.arg, parseScopeName("arg").?);
    try std.testing.expectEqual(@as(?Scope, null), parseScopeName("invalid"));
}

test "scoped logger - basic" {
    const log = scoped(.tui);

    // These should not crash (output depends on env var)
    log.trace("trace message", .{});
    log.debug("debug message", .{});
    log.info("info message", .{});
    log.warn("warn message", .{});
    log.err("error message", .{});
}

test "scoped logger - with args" {
    const log = scoped(.arg);

    log.info("Processing arg {d}: {s}", .{ 1, "test" });
    log.warn("Invalid flag: {s}", .{"--unknown"});
    log.err("Failed with error: {s}", .{"SomeError"});
}

test "multiple scopes" {
    const tui_log = scoped(.tui);
    const arg_log = scoped(.arg);

    tui_log.info("TUI initialized", .{});
    arg_log.debug("Parsing args", .{});
}
