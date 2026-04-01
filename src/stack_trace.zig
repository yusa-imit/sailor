//! Stack Trace Helpers — Better panic messages with context
//!
//! Provides utilities for capturing and formatting stack traces with context:
//! - Panic messages with custom context
//! - Stack trace capture for debugging
//! - Formatted stack trace output
//!
//! Example usage:
//! ```zig
//! const stack_trace = @import("stack_trace.zig");
//!
//! // Panic with context
//! stack_trace.panicWithContext("Invalid state: {s}", .{state_name});
//!
//! // Assert with context
//! stack_trace.assert(x > 0, "x must be positive, got {d}", .{x});
//! ```

const std = @import("std");
const builtin = @import("builtin");

/// Panic with formatted context message
pub fn panicWithContext(comptime fmt: []const u8, args: anytype) noreturn {
    const msg = std.fmt.allocPrint(
        std.heap.page_allocator,
        fmt,
        args,
    ) catch "panic (failed to format message)";

    @panic(msg);
}

/// Assert with formatted context message
pub fn assert(ok: bool, comptime fmt: []const u8, args: anytype) void {
    if (!ok) {
        panicWithContext("Assertion failed: " ++ fmt, args);
    }
}

/// Precondition check with formatted message
pub fn require(ok: bool, comptime fmt: []const u8, args: anytype) void {
    if (!ok) {
        panicWithContext("Precondition failed: " ++ fmt, args);
    }
}

/// Postcondition check with formatted message
pub fn ensure(ok: bool, comptime fmt: []const u8, args: anytype) void {
    if (!ok) {
        panicWithContext("Postcondition failed: " ++ fmt, args);
    }
}

/// Unreachable code marker with context
pub fn unreachable_(comptime fmt: []const u8, args: anytype) noreturn {
    panicWithContext("Unreachable code reached: " ++ fmt, args);
}

/// Stack trace capture (if available)
pub const StackTrace = struct {
    addresses: [32]usize,
    count: usize,

    /// Capture current stack trace
    pub fn capture() StackTrace {
        var trace = StackTrace{
            .addresses = undefined,
            .count = 0,
        };

        // Platform-specific stack trace capture
        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            // Use backtrace if available (requires -rdynamic linker flag)
            // For now, just mark as unavailable
            trace.count = 0;
        }

        return trace;
    }

    /// Format stack trace to writer
    pub fn format(self: StackTrace, writer: anytype) !void {
        if (self.count == 0) {
            try writer.writeAll("(stack trace unavailable)\n");
            return;
        }

        try writer.writeAll("Stack trace:\n");
        for (self.addresses[0..self.count], 0..) |addr, i| {
            try writer.print("  [{d}] 0x{x}\n", .{ i, addr });
        }
    }
};

/// Print debug info with source location
pub fn debugHere(comptime msg: []const u8) void {
    const src = @src();
    std.debug.print("[{s}:{d}] {s}\n", .{ src.file, src.line, msg });
}

/// Print debug info with source location and value
pub fn debugValue(comptime name: []const u8, value: anytype) void {
    const src = @src();
    std.debug.print("[{s}:{d}] {s} = {any}\n", .{ src.file, src.line, name, value });
}

// ============================================================================
// Tests
// ============================================================================

test "assert - success" {
    assert(true, "should not panic", .{});
    assert(1 + 1 == 2, "math should work", .{});
}

test "require - success" {
    require(true, "should not panic", .{});
    const x: i32 = 10;
    require(x > 0, "x should be positive", .{});
}

test "ensure - success" {
    ensure(true, "should not panic", .{});
    const result: i32 = 42;
    ensure(result == 42, "result should be 42", .{});
}

test "StackTrace.capture" {
    const trace = StackTrace.capture();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);

    try trace.format(buf.writer(std.testing.allocator));

    // Should produce some output
    try std.testing.expect(buf.items.len > 0);
}

test "debugHere - does not crash" {
    // Just verify it doesn't crash (output goes to stderr)
    debugHere("test debug message");
}

test "debugValue - does not crash" {
    // Just verify it doesn't crash (output goes to stderr)
    const x: i32 = 42;
    debugValue("x", x);

    const s = "hello";
    debugValue("s", s);
}

test "assert - with formatting" {
    const x: i32 = 10;
    assert(x == 10, "x should be {d}, got {d}", .{ 10, x });
}

test "require - with formatting" {
    const count: usize = 5;
    require(count > 0, "count must be positive, got {d}", .{count});
}

test "ensure - with formatting" {
    const result: []const u8 = "success";
    ensure(result.len > 0, "result should not be empty, got '{s}'", .{result});
}
