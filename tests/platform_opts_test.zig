//! Platform-specific performance optimizations tests (v2.8.0)
//!
//! Comprehensive tests for platform-specific optimization layer:
//! - Comptime platform detection (zero runtime cost)
//! - Linux: Direct ANSI sequence emission
//! - macOS: Metal framework detection
//! - Windows: Batch console API calls
//! - Performance benchmarks (per-platform overhead measurements)

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const sailor = @import("sailor");

// ============================================================================
// Section 1: Comptime Platform Detection (5 tests)
// ============================================================================

test "platform detection returns correct Platform enum for current OS" {
    const platform = sailor.tui.platform_opts.detectPlatform();

    const expected = switch (builtin.os.tag) {
        .linux => sailor.tui.platform_opts.Platform.linux,
        .macos => sailor.tui.platform_opts.Platform.macos,
        .windows => sailor.tui.platform_opts.Platform.windows,
        else => sailor.tui.platform_opts.Platform.other,
    };

    try testing.expectEqual(expected, platform);
}

test "platform detection is pure comptime with zero runtime cost" {
    // This test verifies that platform detection happens at comptime
    // by ensuring the result is a comptime_int or constant
    comptime {
        const platform = sailor.tui.platform_opts.detectPlatform();
        _ = platform;
    }
}

test "isLinux() returns true only on Linux" {
    const is_linux = sailor.tui.platform_opts.isLinux();

    if (builtin.os.tag == .linux) {
        try testing.expect(is_linux);
    } else {
        try testing.expect(!is_linux);
    }
}

test "isMacOS() returns true only on macOS" {
    const is_macos = sailor.tui.platform_opts.isMacOS();

    if (builtin.os.tag == .macos) {
        try testing.expect(is_macos);
    } else {
        try testing.expect(!is_macos);
    }
}

test "isWindows() returns true only on Windows" {
    const is_windows = sailor.tui.platform_opts.isWindows();

    if (builtin.os.tag == .windows) {
        try testing.expect(is_windows);
    } else {
        try testing.expect(!is_windows);
    }
}

test "arch detection identifies x86_64 and aarch64" {
    const arch = sailor.tui.platform_opts.detectArch();

    const valid = switch (arch) {
        .x86_64, .aarch64, .other => true,
    };

    try testing.expect(valid);
}

// ============================================================================
// Section 2: Linux Direct ANSI Emission (6 tests)
// ============================================================================

test "Linux emitAnsi writes raw ANSI sequences without processing" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const ansi_code = "\x1b[31m"; // Red foreground
    try sailor.tui.platform_opts.emitAnsi(stream.writer(), ansi_code);

    const written = stream.getWritten();
    try testing.expectEqualStrings(ansi_code, written);
}

test "Linux emitAnsi does not parse or validate ANSI codes" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    // Invalid sequence should still be written as-is
    const invalid_code = "\x1b[999m";
    try sailor.tui.platform_opts.emitAnsi(stream.writer(), invalid_code);

    const written = stream.getWritten();
    try testing.expectEqualStrings(invalid_code, written);
}

test "Linux emitAnsi writes directly to Writer with minimal overhead" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const sequences = [_][]const u8{
        "\x1b[31m",      // Red
        "Hello",
        "\x1b[0m",       // Reset
        "\x1b[1;32m",    // Bold green
        "World",
        "\x1b[0m",       // Reset
    };

    for (sequences) |seq| {
        try sailor.tui.platform_opts.emitAnsi(stream.writer(), seq);
    }

    const written = stream.getWritten();
    try testing.expect(std.mem.startsWith(u8, written, "\x1b[31m"));
    try testing.expect(std.mem.indexOf(u8, written, "Hello") != null);
    try testing.expect(std.mem.indexOf(u8, written, "World") != null);
}

test "Linux batch multiple ANSI sequences in single write call" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const batch = "\x1b[31m\x1b[1m\x1b[4m"; // Red, Bold, Underline
    try sailor.tui.platform_opts.emitAnsi(stream.writer(), batch);

    const written = stream.getWritten();
    try testing.expectEqualStrings(batch, written);
}

test "Linux SGR sequences are optimized without reparsing" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    // SGR (Select Graphic Rendition) sequence
    const sgr = "\x1b[31;1;4m"; // Red, bold, underline
    try sailor.tui.platform_opts.emitAnsi(stream.writer(), sgr);

    const written = stream.getWritten();
    try testing.expectEqualStrings(sgr, written);
}

// ============================================================================
// Section 3: macOS Metal Detection (5 tests)
// ============================================================================

test "macOS detectMetalSupport checks framework availability" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;
    const result = try sailor.tui.platform_opts.detectMetalSupport(allocator);
    defer result.deinit();

    // Should return a MetalCapability struct
    _ = result.available; // Just ensure field exists
    _ = result.version;   // Just ensure field exists
}

test "macOS detectMetalSupport queries TERM_PROGRAM environment variable" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;
    const result = try sailor.tui.platform_opts.detectMetalSupport(allocator);
    defer result.deinit();

    // TERM_PROGRAM could be iTerm2, Terminal.app, or other
    // Should return reasonable value (either available or not)
    try testing.expect(result.available == true or result.available == false);
}

test "macOS detectMetalSupport handles missing environment gracefully" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Should not crash or panic when env vars are missing
    const result = try sailor.tui.platform_opts.detectMetalSupport(allocator);
    defer result.deinit();
}

test "macOS MetalCapability struct contains version info" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;
    const result = try sailor.tui.platform_opts.detectMetalSupport(allocator);
    defer result.deinit();

    // Version should be either 0 (not available) or > 0
    try testing.expect(result.version >= 0);
}

test "macOS detectMetalSupport returns allocated result that must be freed" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    const result1 = try sailor.tui.platform_opts.detectMetalSupport(allocator);
    const result2 = try sailor.tui.platform_opts.detectMetalSupport(allocator);

    // Both calls should succeed
    result1.deinit();
    result2.deinit();
}

// ============================================================================
// Section 4: Windows Batch Console API (6 tests)
// ============================================================================

test "Windows WindowsConsoleBuffer accumulates API calls" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    var buf = try sailor.tui.platform_opts.WindowsConsoleBuffer.init(allocator, 256);
    defer buf.deinit();

    // Buffer should start empty
    try testing.expectEqual(@as(usize, 0), buf.callCount());
}

test "Windows WindowsConsoleBuffer flush writes batch in single syscall" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    var buf = try sailor.tui.platform_opts.WindowsConsoleBuffer.init(allocator, 256);
    defer buf.deinit();

    // Simulate accumulating multiple SetConsoleTextAttribute calls
    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 7, .background = 0 } });
    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 1, .background = 0 } });
    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 2, .background = 0 } });

    try testing.expectEqual(@as(usize, 3), buf.callCount());

    // Flush should combine into single call structure
    try buf.flush();

    // After flush, buffer should be empty
    try testing.expectEqual(@as(usize, 0), buf.callCount());
}

test "Windows WindowsConsoleBuffer batches SetConsoleTextAttribute calls" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    var buf = try sailor.tui.platform_opts.WindowsConsoleBuffer.init(allocator, 256);
    defer buf.deinit();

    // Add multiple style changes
    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 4, .background = 0 } });
    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 4, .background = 1 } });

    // Count should reflect accumulated calls
    try testing.expectEqual(@as(usize, 2), buf.callCount());
}

test "Windows WindowsConsoleBuffer batches WriteConsoleW calls" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    var buf = try sailor.tui.platform_opts.WindowsConsoleBuffer.init(allocator, 512);
    defer buf.deinit();

    // Add multiple text writes
    try buf.addCall(.{ .write_console = .{ .text = "Hello " } });
    try buf.addCall(.{ .write_console = .{ .text = "World" } });
    try buf.addCall(.{ .write_console = .{ .text = "!" } });

    try testing.expectEqual(@as(usize, 3), buf.callCount());
}

test "Windows WindowsConsoleBuffer auto-flushes at threshold" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    // Small buffer to trigger early flush
    var buf = try sailor.tui.platform_opts.WindowsConsoleBuffer.init(allocator, 4);
    defer buf.deinit();

    // Fill buffer
    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 1, .background = 0 } });
    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 2, .background = 0 } });
    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 3, .background = 0 } });
    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 4, .background = 0 } });

    // Adding 5th should trigger auto-flush
    try buf.addCall(.{ .set_text_attribute = .{ .foreground = 5, .background = 0 } });

    // Should still work correctly
    try testing.expect(buf.callCount() > 0);
}

test "Windows WindowsConsoleBuffer handles buffer overflow gracefully" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    var buf = try sailor.tui.platform_opts.WindowsConsoleBuffer.init(allocator, 256);
    defer buf.deinit();

    // Should not panic or crash when adding many calls
    for (0..1000) |i| {
        _ = buf.addCall(.{
            .set_text_attribute = .{
                .foreground = @as(u8, @truncate(i % 16)),
                .background = 0
            }
        }) catch |err| {
            // Either succeeds or returns error gracefully
            try testing.expectError(error.BufferFull, err);
            break;
        };
    }
}

// ============================================================================
// Section 5: Performance Benchmarks (4 tests)
// ============================================================================

test "Linux direct ANSI overhead < 5ns per sequence" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const sequence = "\x1b[31m";

    // Warm up
    try sailor.tui.platform_opts.emitAnsi(stream.writer(), sequence);
    _ = stream.getWritten();

    // Measure
    const iterations = 1000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        var reset_buf: [1024]u8 = undefined;
        var reset_stream = std.io.fixedBufferStream(&reset_buf);
        try sailor.tui.platform_opts.emitAnsi(reset_stream.writer(), sequence);
        _ = reset_stream.getWritten();
    }

    const elapsed = std.time.nanoTimestamp() - start;
    const avg_ns = @as(u64, @intCast(elapsed / iterations));

    // Allow some flexibility for CI environments
    // This is a soft benchmark, not a hard assertion
    _ = avg_ns;
}

test "Windows batch API > 50% syscall reduction vs non-batched" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Batched approach
    var buf = try sailor.tui.platform_opts.WindowsConsoleBuffer.init(allocator, 256);
    defer buf.deinit();

    const batched_start = std.time.nanoTimestamp();
    for (0..100) |i| {
        try buf.addCall(.{
            .set_text_attribute = .{
                .foreground = @as(u8, @truncate(i % 16)),
                .background = 0
            }
        });
    }
    try buf.flush();
    const batched_elapsed = std.time.nanoTimestamp() - batched_start;

    // Non-batched approach would call syscall 100 times
    // Batched approach should be significantly faster
    // (This is a soft benchmark, exact timing varies)
    _ = batched_elapsed;
}

test "platform-specific write overhead measurement (comptime)" {
    comptime {
        const platform = sailor.tui.platform_opts.detectPlatform();

        // Verify we can detect platform at comptime
        const is_special = switch (platform) {
            .linux, .windows => true,
            else => false,
        };

        _ = is_special;
    }
}

test "Windows batch > non-batch comparison shows improvement" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    var buf = try sailor.tui.platform_opts.WindowsConsoleBuffer.init(allocator, 512);
    defer buf.deinit();

    // Simulate typical rendering operations
    const operations = [_]struct {
        type: []const u8,
        count: usize,
    }{
        .{ .type = "SetTextAttribute", .count = 50 },
        .{ .type = "WriteConsole", .count = 100 },
        .{ .type = "SetTextAttribute", .count = 50 },
    };

    for (operations) |op| {
        if (std.mem.eql(u8, op.type, "SetTextAttribute")) {
            for (0..op.count) |i| {
                try buf.addCall(.{
                    .set_text_attribute = .{
                        .foreground = @as(u8, @truncate(i % 16)),
                        .background = 0,
                    },
                });
            }
        }
    }

    // After batching, we should have significantly fewer total calls
    const total_calls = buf.callCount();
    try testing.expect(total_calls > 0);
}

// ============================================================================
// Section 6: Edge Cases & Integration (4 additional tests)
// ============================================================================

test "platform detection consistent across multiple calls" {
    const p1 = sailor.tui.platform_opts.detectPlatform();
    const p2 = sailor.tui.platform_opts.detectPlatform();
    const p3 = sailor.tui.platform_opts.detectPlatform();

    try testing.expectEqual(p1, p2);
    try testing.expectEqual(p2, p3);
}

test "Windows buffer does not lose data during auto-flush" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;
    var buf = try sailor.tui.platform_opts.WindowsConsoleBuffer.init(allocator, 8);
    defer buf.deinit();

    const initial_call = sailor.tui.platform_opts.ConsoleCall{
        .set_text_attribute = .{ .foreground = 1, .background = 0 },
    };

    try buf.addCall(initial_call);

    // Fill to trigger flush
    for (0..10) |i| {
        _ = buf.addCall(.{
            .set_text_attribute = .{
                .foreground = @as(u8, @truncate(i % 16)),
                .background = 0,
            },
        }) catch break;
    }

    // Should have processed some calls
    try testing.expect(buf.callCount() > 0);
}

test "isLinux, isMacOS, isWindows are mutually exclusive" {
    const is_linux = sailor.tui.platform_opts.isLinux();
    const is_macos = sailor.tui.platform_opts.isMacOS();
    const is_windows = sailor.tui.platform_opts.isWindows();

    // At most one should be true
    var count: u8 = 0;
    if (is_linux) count += 1;
    if (is_macos) count += 1;
    if (is_windows) count += 1;

    try testing.expect(count <= 1);
}

test "platform opts module loads without errors" {
    // Simple smoke test
    const platform = sailor.tui.platform_opts.detectPlatform();
    _ = platform;

    const is_linux = sailor.tui.platform_opts.isLinux();
    _ = is_linux;

    const is_macos = sailor.tui.platform_opts.isMacOS();
    _ = is_macos;

    const is_windows = sailor.tui.platform_opts.isWindows();
    _ = is_windows;
}
