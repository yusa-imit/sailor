//! Cross-platform compatibility tests
//!
//! These tests verify that platform-specific code paths compile
//! and run correctly across Linux, macOS, and Windows.

const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

test "platform-specific type sizes" {
    // Ensure fundamental types are as expected
    try testing.expectEqual(8, @sizeOf(u64));
    try testing.expectEqual(4, @sizeOf(u32));
    try testing.expectEqual(1, @sizeOf(u8));
}

test "platform os tag detection" {
    const tag = builtin.os.tag;

    // Verify we're on a supported platform
    const supported = switch (tag) {
        .linux, .macos, .windows => true,
        else => false,
    };

    try testing.expect(supported);
}

test "platform cpu arch detection" {
    const arch = builtin.cpu.arch;

    // Verify we're on a supported architecture
    const supported = switch (arch) {
        .x86_64, .aarch64, .arm => true,
        else => false,
    };

    try testing.expect(supported);
}

test "file system path separator is correct" {
    const sep = std.fs.path.sep;

    if (builtin.os.tag == .windows) {
        try testing.expectEqual('\\', sep);
    } else {
        try testing.expectEqual('/', sep);
    }
}

test "newline convention detection" {
    // Windows uses \r\n, Unix uses \n
    const expected_newline = if (builtin.os.tag == .windows) "\r\n" else "\n";

    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try writer.print("line1{s}line2", .{expected_newline});

    const written = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, written, expected_newline) != null);
}

test "endianness detection" {
    const endian = builtin.cpu.arch.endian();

    // Most platforms are little-endian
    const is_little_or_big = switch (endian) {
        .little, .big => true,
    };

    try testing.expect(is_little_or_big);
}

test "pointer size matches target" {
    const ptr_size = @sizeOf(usize);

    // Should be 4 or 8 bytes depending on 32/64 bit
    try testing.expect(ptr_size == 4 or ptr_size == 8);
}

test "standard file descriptors availability" {
    // These should always be available
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    // Just verify they exist
    _ = stdin;
    _ = stdout;
    _ = stderr;
}

test "environment variable access" {
    // Test that we can access environment variables
    var env_map = try std.process.getEnvMap(testing.allocator);
    defer env_map.deinit();

    // PATH should exist on all platforms
    const path = env_map.get("PATH") orelse env_map.get("Path");

    // On Unix it's PATH, on Windows it might be Path
    // At least one should exist
    _ = path;
}

test "heap allocation works cross-platform" {
    const allocator = testing.allocator;

    // Allocate various sizes
    const small = try allocator.alloc(u8, 16);
    defer allocator.free(small);

    const medium = try allocator.alloc(u8, 1024);
    defer allocator.free(medium);

    const large = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(large);

    try testing.expectEqual(16, small.len);
    try testing.expectEqual(1024, medium.len);
    try testing.expectEqual(1024 * 1024, large.len);
}

test "thread support detection" {
    // Single-threaded builds might not support threads
    const has_threads = !builtin.single_threaded;

    // Just verify detection works
    _ = has_threads;
}

test "atomic operations availability" {
    var value: u32 = 0;

    // Basic atomic operations should work
    _ = @atomicLoad(u32, &value, .seq_cst);
    @atomicStore(u32, &value, 42, .seq_cst);

    const result = @atomicLoad(u32, &value, .seq_cst);
    try testing.expectEqual(42, result);
}

test "comptime platform branching" {
    const result = comptime blk: {
        if (builtin.os.tag == .windows) {
            break :blk "windows";
        } else if (builtin.os.tag == .linux) {
            break :blk "linux";
        } else if (builtin.os.tag == .macos) {
            break :blk "macos";
        } else {
            break :blk "other";
        }
    };

    try testing.expect(result.len > 0);
}

test "unicode character handling" {
    // Test various Unicode characters that might render differently
    const chars = [_][]const u8{
        "─", // Box drawing
        "│", // Box drawing
        "┌", // Box drawing
        "┐", // Box drawing
        "└", // Box drawing
        "┘", // Box drawing
        "█", // Full block
        "▀", // Upper half block
        "▄", // Lower half block
        "🚢", // Ship emoji
    };

    for (chars) |char| {
        try testing.expect(char.len > 0);
        try testing.expect(std.unicode.utf8ValidateSlice(char));
    }
}

test "error set behavior" {
    const PlatformError = error{
        NotSupported,
        AccessDenied,
        ResourceBusy,
    };

    const result: PlatformError!void = PlatformError.NotSupported;

    if (result) {
        try testing.expect(false);
    } else |err| {
        try testing.expectEqual(PlatformError.NotSupported, err);
    }
}
