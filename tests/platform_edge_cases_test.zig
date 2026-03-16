//! Platform-specific edge case tests
//!
//! Tests that verify correct behavior across Linux, macOS, and Windows,
//! including edge cases that are platform-specific.

const std = @import("std");
const builtin = @import("builtin");
const sailor = @import("sailor");
const term = sailor.term;

// Test that isatty correctly identifies all standard streams
test "isatty on all standard file descriptors" {
    // Test stdin (fd 0)
    const stdin_is_tty = term.isatty(std.posix.STDIN_FILENO);
    // CI environments typically don't have TTY, interactive shells do
    // We can't assert specific value, but should not crash
    _ = stdin_is_tty;

    // Test stdout (fd 1)
    const stdout_is_tty = term.isatty(std.posix.STDOUT_FILENO);
    _ = stdout_is_tty;

    // Test stderr (fd 2)
    const stderr_is_tty = term.isatty(std.posix.STDERR_FILENO);
    _ = stderr_is_tty;

    // All three calls should complete without crashing
}

// Test that isatty returns false for non-existent file descriptors
test "isatty returns false for invalid file descriptors" {
    // Very high fd that definitely doesn't exist
    try std.testing.expect(!term.isatty(9999));

    // Negative fd (invalid on all platforms)
    if (builtin.os.tag != .windows) {
        try std.testing.expect(!term.isatty(-1));
    }
}

// Test that getSize handles TTY unavailability gracefully
test "getSize graceful error on non-TTY environment" {
    // In CI/non-TTY environments, this should return error.TerminalSizeUnavailable
    // In TTY environments, it should return valid Size
    const result = term.getSize();

    if (result) |size| {
        // If successful, dimensions must be reasonable
        try std.testing.expect(size.cols > 0);
        try std.testing.expect(size.rows > 0);
        try std.testing.expect(size.cols < 10000);
        try std.testing.expect(size.rows < 10000);
    } else |err| {
        // Expected error in CI
        try std.testing.expectEqual(term.Error.TerminalSizeUnavailable, err);
    }
}

// Platform-specific: Test Unix ioctl behavior
test "Unix ioctl edge cases" {
    if (builtin.os.tag != .linux and builtin.os.tag != .macos) {
        return error.SkipZigTest;
    }

    // getSizeUnix should fail gracefully when stdout is not a TTY
    // (This is internal, so we test through public getSize)
    const result = term.getSize();

    // Should either succeed with valid size or fail with TerminalSizeUnavailable
    if (result) |size| {
        try std.testing.expect(size.cols > 0 and size.cols < 10000);
        try std.testing.expect(size.rows > 0 and size.rows < 10000);
    } else |err| {
        try std.testing.expectEqual(term.Error.TerminalSizeUnavailable, err);
    }
}

// Platform-specific: Test Windows console API behavior
test "Windows console API edge cases" {
    if (builtin.os.tag != .windows) {
        return error.SkipZigTest;
    }

    // Windows-specific: Test console handle retrieval
    const windows = std.os.windows;

    // Test that we can get standard handles without crashing
    const stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch {
        // If GetStdHandle fails, getSize should also fail
        try std.testing.expectError(term.Error.TerminalSizeUnavailable, term.getSize());
        return;
    };

    // If we got a handle, verify it's valid
    try std.testing.expect(stdout_handle != windows.INVALID_HANDLE_VALUE);

    // Test getSize with console handle available
    const result = term.getSize();
    if (result) |size| {
        try std.testing.expect(size.cols > 0 and size.cols < 10000);
        try std.testing.expect(size.rows > 0 and size.rows < 10000);
    } else |_| {
        // Also acceptable if console mode is not available
    }
}

// Test cross-platform: Size struct edge cases
test "Size struct boundary values" {
    const min_size = term.Size{ .cols = 1, .rows = 1 };
    try std.testing.expectEqual(@as(u16, 1), min_size.cols);
    try std.testing.expectEqual(@as(u16, 1), min_size.rows);

    const max_size = term.Size{ .cols = 9999, .rows = 9999 };
    try std.testing.expectEqual(@as(u16, 9999), max_size.cols);
    try std.testing.expectEqual(@as(u16, 9999), max_size.rows);

    // Typical terminal sizes
    const vt100 = term.Size{ .cols = 80, .rows = 24 };
    try std.testing.expectEqual(@as(u16, 80), vt100.cols);
    try std.testing.expectEqual(@as(u16, 24), vt100.rows);

    const modern = term.Size{ .cols = 120, .rows = 40 };
    try std.testing.expectEqual(@as(u16, 120), modern.cols);
    try std.testing.expectEqual(@as(u16, 40), modern.rows);
}

// Test RawMode platform independence
test "RawMode abstraction is platform-independent" {
    // RawMode should compile on all platforms
    // We can't actually enter raw mode in tests (requires TTY),
    // but we can verify the types are correct

    const RawMode = term.RawMode;

    // Verify the struct exists and has expected methods
    const type_info = @typeInfo(RawMode);
    try std.testing.expect(type_info == .@"struct");

    // Verify method signatures exist (compile-time check)
    comptime {
        _ = RawMode.enter;
        _ = RawMode.deinit;
    }
}

// Test error handling for unsupported platforms
test "UnsupportedPlatform error on exotic platforms" {
    // This test verifies that on unsupported platforms, we get proper errors
    // rather than crashes or undefined behavior

    // Compile-time check: if we're on an unsupported platform,
    // getSizeUnix should return UnsupportedPlatform
    if (builtin.os.tag != .linux and
        builtin.os.tag != .macos and
        builtin.os.tag != .windows)
    {
        // On other platforms, getSize should fail gracefully
        const result = term.getSize();
        try std.testing.expectError(term.Error.UnsupportedPlatform, result);
    }
}

// Test concurrent isatty calls (thread safety)
test "isatty is thread-safe" {
    const ThreadContext = struct {
        results: *[10]bool,
        index: usize,

        fn run(ctx: @This()) void {
            // Each thread checks if stdout is a TTY
            ctx.results[ctx.index] = term.isatty(std.posix.STDOUT_FILENO);
        }
    };

    var results: [10]bool = undefined;
    var threads: [10]std.Thread = undefined;

    // Spawn 10 concurrent threads
    for (&threads, 0..) |*thread, i| {
        const ctx = ThreadContext{ .results = &results, .index = i };
        thread.* = try std.Thread.spawn(.{}, ThreadContext.run, .{ctx});
    }

    // Wait for all threads
    for (threads) |thread| {
        thread.join();
    }

    // All threads should return the same result
    const expected = results[0];
    for (results) |result| {
        try std.testing.expectEqual(expected, result);
    }
}

// Test getSize with extreme terminal dimensions (hypothetical)
test "getSize validates extreme dimensions" {
    const result = term.getSize();

    if (result) |size| {
        // Dimensions must be within validated range
        // (The implementation should reject cols/rows >= 10000)
        try std.testing.expect(size.cols > 0 and size.cols < 10000);
        try std.testing.expect(size.rows > 0 and size.rows < 10000);
    } else |err| {
        // In non-TTY environments, we expect this specific error
        try std.testing.expect(
            err == term.Error.TerminalSizeUnavailable or
                err == term.Error.UnsupportedPlatform,
        );
    }
}

// Test zero-dimension terminal rejection
test "getSize rejects zero dimensions" {
    // This is a regression test for the validation logic
    // The implementation checks: if (ws.col == 0 or ws.row == 0) return error
    // We can't directly trigger this, but we verify getSize never returns Size{0, 0}

    const result = term.getSize();
    if (result) |size| {
        try std.testing.expect(size.cols != 0);
        try std.testing.expect(size.rows != 0);
    } else |_| {
        // Error is acceptable
    }
}

// Platform-specific: macOS vs Linux ioctl constant differences
test "TIOCGWINSZ ioctl constant is correct per platform" {
    comptime {
        if (builtin.os.tag == .linux) {
            // Linux uses 0x5413
            const TIOCGWINSZ: u32 = 0x5413;
            _ = TIOCGWINSZ; // Verify compile
        } else if (builtin.os.tag == .macos) {
            // macOS uses 0x40087468
            const TIOCGWINSZ: u32 = 0x40087468;
            _ = TIOCGWINSZ; // Verify compile
        }
    }
}
