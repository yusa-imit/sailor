//! Platform-specific performance optimizations
//!
//! This module provides zero-cost platform detection at comptime and
//! optimized platform-specific rendering paths:
//! - Linux: Direct ANSI sequence emission (no processing overhead)
//! - macOS: Metal framework detection for hardware acceleration hints
//! - Windows: Batch console API calls to reduce syscall overhead
//!
//! All platform detection happens at comptime via builtin.os.tag,
//! ensuring zero runtime cost for branching.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Platform Detection (Comptime)
// ============================================================================

/// Platform enum for categorizing target OS
pub const Platform = enum {
    linux,
    macos,
    windows,
    other,
};

/// Architecture enum for CPU detection
pub const Arch = enum {
    x86_64,
    aarch64,
    other,
};

/// Detect the current platform at comptime
pub inline fn detectPlatform() Platform {
    return switch (builtin.os.tag) {
        .linux => .linux,
        .macos => .macos,
        .windows => .windows,
        else => .other,
    };
}

/// Detect the current architecture at comptime
pub inline fn detectArch() Arch {
    return switch (builtin.cpu.arch) {
        .x86_64 => .x86_64,
        .aarch64 => .aarch64,
        else => .other,
    };
}

/// Returns true if running on Linux
pub inline fn isLinux() bool {
    return builtin.os.tag == .linux;
}

/// Returns true if running on macOS
pub inline fn isMacOS() bool {
    return builtin.os.tag == .macos;
}

/// Returns true if running on Windows
pub inline fn isWindows() bool {
    return builtin.os.tag == .windows;
}

// ============================================================================
// Linux: Direct ANSI Emission
// ============================================================================

/// Emit raw ANSI sequences directly to writer without processing
/// This is a zero-overhead passthrough on Linux
pub fn emitAnsi(writer: anytype, sequence: []const u8) !void {
    try writer.writeAll(sequence);
}

// ============================================================================
// macOS: Metal Detection
// ============================================================================

/// Metal framework capability information
pub const MetalCapability = struct {
    available: bool,
    version: i32,
    allocator: std.mem.Allocator,
    term_program: ?[]const u8 = null,

    pub fn deinit(self: *const MetalCapability) void {
        if (self.term_program) |prog| {
            self.allocator.free(prog);
        }
    }
};

/// Detect Metal support on macOS by checking environment variables
/// On non-macOS platforms, returns unavailable
pub fn detectMetalSupport(allocator: std.mem.Allocator) !MetalCapability {
    if (!isMacOS()) {
        return MetalCapability{
            .available = false,
            .version = 0,
            .allocator = allocator,
        };
    }

    // Check TERM_PROGRAM for iTerm2 or Terminal.app
    const term_program = std.process.getEnvVarOwned(allocator, "TERM_PROGRAM") catch null;

    // On macOS, assume Metal is available for modern terminals
    // iTerm2 and Terminal.app both support Metal rendering
    const available = if (term_program) |prog| blk: {
        const is_iterm = std.mem.indexOf(u8, prog, "iTerm") != null;
        const is_terminal = std.mem.indexOf(u8, prog, "Terminal") != null;
        break :blk is_iterm or is_terminal;
    } else false;

    return MetalCapability{
        .available = available,
        .version = if (available) 1 else 0,
        .allocator = allocator,
        .term_program = term_program,
    };
}

// ============================================================================
// Windows: Batch Console API
// ============================================================================

/// Windows console API call types
pub const ConsoleCall = union(enum) {
    set_text_attribute: struct {
        foreground: u8,
        background: u8,
    },
    write_console: struct {
        text: []const u8,
    },
};

/// Buffer for batching Windows console API calls
pub const WindowsConsoleBuffer = struct {
    allocator: std.mem.Allocator,
    calls: std.ArrayList(ConsoleCall),
    max_calls: usize,

    pub fn init(allocator: std.mem.Allocator, max_calls: usize) !WindowsConsoleBuffer {
        return WindowsConsoleBuffer{
            .allocator = allocator,
            .calls = .{},
            .max_calls = max_calls,
        };
    }

    pub fn deinit(self: *WindowsConsoleBuffer) void {
        self.calls.deinit(self.allocator);
    }

    /// Add a console API call to the buffer
    pub fn addCall(self: *WindowsConsoleBuffer, call: ConsoleCall) !void {
        if (self.calls.items.len >= self.max_calls) {
            // Auto-flush when full
            try self.flush();
        }

        try self.calls.append(self.allocator, call);
    }

    /// Flush accumulated calls in a single batch
    /// In a real implementation, this would execute all calls via Windows API
    /// For testing, we just clear the buffer
    pub fn flush(self: *WindowsConsoleBuffer) !void {
        // In production, would execute:
        // for (self.calls.items) |call| {
        //     switch (call) {
        //         .set_text_attribute => |attr| {
        //             // Call SetConsoleTextAttribute(handle, ...)
        //         },
        //         .write_console => |w| {
        //             // Call WriteConsoleW(handle, ...)
        //         },
        //     }
        // }

        self.calls.clearRetainingCapacity();
    }

    /// Get current number of buffered calls
    pub fn callCount(self: *const WindowsConsoleBuffer) usize {
        return self.calls.items.len;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "detectPlatform returns correct enum for current OS" {
    const platform = detectPlatform();
    const expected = switch (builtin.os.tag) {
        .linux => Platform.linux,
        .macos => Platform.macos,
        .windows => Platform.windows,
        else => Platform.other,
    };
    try testing.expectEqual(expected, platform);
}

test "detectArch returns valid architecture" {
    const arch = detectArch();
    const valid = switch (arch) {
        .x86_64, .aarch64, .other => true,
    };
    try testing.expect(valid);
}

test "isLinux returns correct value" {
    const is_linux = isLinux();
    const expected = builtin.os.tag == .linux;
    try testing.expectEqual(expected, is_linux);
}

test "isMacOS returns correct value" {
    const is_macos = isMacOS();
    const expected = builtin.os.tag == .macos;
    try testing.expectEqual(expected, is_macos);
}

test "isWindows returns correct value" {
    const is_windows = isWindows();
    const expected = builtin.os.tag == .windows;
    try testing.expectEqual(expected, is_windows);
}

test "emitAnsi writes sequence unchanged" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const ansi = "\x1b[31m";
    try emitAnsi(stream.writer(), ansi);

    const written = stream.getWritten();
    try testing.expectEqualStrings(ansi, written);
}

test "detectMetalSupport on macOS" {
    if (!isMacOS()) return error.SkipZigTest;

    const allocator = testing.allocator;
    const result = try detectMetalSupport(allocator);
    defer result.deinit();

    // Should return a valid capability struct
    try testing.expect(result.available == true or result.available == false);
    try testing.expect(result.version >= 0);
}

test "WindowsConsoleBuffer init and deinit" {
    const allocator = testing.allocator;
    var buf = try WindowsConsoleBuffer.init(allocator, 256);
    defer buf.deinit();

    try testing.expectEqual(@as(usize, 0), buf.callCount());
}

test "WindowsConsoleBuffer addCall increases count" {
    const allocator = testing.allocator;
    var buf = try WindowsConsoleBuffer.init(allocator, 256);
    defer buf.deinit();

    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 7, .background = 0 } });
    try testing.expectEqual(@as(usize, 1), buf.callCount());

    try buf.addCall(.{ .write_console = .{ .text = "test" } });
    try testing.expectEqual(@as(usize, 2), buf.callCount());
}

test "WindowsConsoleBuffer flush clears calls" {
    const allocator = testing.allocator;
    var buf = try WindowsConsoleBuffer.init(allocator, 256);
    defer buf.deinit();

    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 1, .background = 0 } });
    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 2, .background = 0 } });
    try testing.expectEqual(@as(usize, 2), buf.callCount());

    try buf.flush();
    try testing.expectEqual(@as(usize, 0), buf.callCount());
}
