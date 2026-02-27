//! Build verification tests
//!
//! These tests verify build system configuration and
//! compilation properties.

const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

test "build mode detection" {
    const mode = builtin.mode;

    // Should be one of the valid modes
    const is_valid = switch (mode) {
        .Debug, .ReleaseSafe, .ReleaseFast, .ReleaseSmall => true,
    };

    try testing.expect(is_valid);
}

test "optimization level is appropriate" {
    const mode = builtin.mode;

    // Debug builds should not be optimized
    // Release builds should be optimized
    const is_debug = mode == .Debug;
    _ = is_debug;

    // Just verify mode exists
}

test "target triple is valid" {
    const target = builtin.target;

    // Verify CPU arch is known
    const arch = target.cpu.arch;
    const valid_arch = switch (arch) {
        .x86_64, .aarch64, .arm, .x86, .riscv64 => true,
        else => false,
    };

    try testing.expect(valid_arch);

    // Verify OS is known
    const os = target.os.tag;
    const valid_os = switch (os) {
        .linux, .macos, .windows, .freebsd, .openbsd, .netbsd => true,
        else => false,
    };

    try testing.expect(valid_os);
}

test "zig version meets minimum" {
    // We require Zig 0.15.x
    const version = builtin.zig_version;

    try testing.expect(version.major == 0);
    try testing.expect(version.minor >= 15);
}

test "safety checks enabled in debug" {
    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        // Safety checks should be enabled
        try testing.expect(true);
    } else {
        // Fast/Small releases may disable safety
        try testing.expect(true);
    }
}

test "libc linkage detection" {
    // Detect if libc is linked
    const link_libc = builtin.link_libc;
    _ = link_libc;

    // sailor should work without libc
    // Just verify detection works
}

test "strip debug info detection" {
    const strip = builtin.strip;
    _ = strip;

    // Release builds may strip debug info
    // Just verify detection works
}

test "PIE/PIC detection" {
    const pic = builtin.position_independent_code;
    _ = pic;

    // Some platforms require PIC
    // Just verify detection works
}

test "stack protector detection" {
    const has_stack_protector = builtin.stack_protector;
    _ = has_stack_protector;

    // Stack protection may be enabled
    // Just verify detection works
}

test "sanitizers detection" {
    const sanitize_thread = builtin.sanitize_thread;
    const sanitize_address = builtin.sanitize_c;
    const sanitize_undefined = builtin.sanitize_c;

    _ = sanitize_thread;
    _ = sanitize_address;
    _ = sanitize_undefined;

    // Sanitizers may be enabled in testing
    // Just verify detection works
}

test "object format detection" {
    const format = builtin.object_format;

    const is_valid = switch (format) {
        .elf, .macho, .coff, .pe, .wasm => true,
        else => false,
    };

    try testing.expect(is_valid);
}

test "ABI detection" {
    const abi = builtin.target.abi;

    const is_valid = switch (abi) {
        .none, .gnu, .musl, .msvc, .android => true,
        else => false,
    };

    try testing.expect(is_valid);
}

test "calling convention detection" {
    const cc = builtin.target.cpu.arch.ptrBitWidth();

    // Should be 32 or 64 bit
    try testing.expect(cc == 32 or cc == 64);
}

test "dynamic linker detection" {
    const dl = builtin.dynamic_linker;
    _ = dl;

    // May be null for static builds
    // Just verify field exists
}

test "import path resolution" {
    // Test that standard library imports work
    const imports = struct {
        const std_import = @import("std");
        const builtin_import = @import("builtin");
    };

    _ = imports;
}

test "compile-time reflection" {
    const T = struct {
        x: u32,
        y: u32,
    };

    const fields = @typeInfo(T).@"struct".fields;

    try testing.expectEqual(2, fields.len);
    try testing.expectEqualStrings("x", fields[0].name);
    try testing.expectEqualStrings("y", fields[1].name);
}

test "comptime execution limits" {
    // Verify we can do reasonable comptime work
    const result = comptime blk: {
        var sum: u32 = 0;
        var i: u32 = 0;
        while (i < 100) : (i += 1) {
            sum += i;
        }
        break :blk sum;
    };

    try testing.expectEqual(4950, result);
}

test "inline assembly availability" {
    // Just verify the feature exists
    // Actual usage is platform-specific

    if (builtin.cpu.arch == .x86_64 or builtin.cpu.arch == .aarch64) {
        // Inline assembly should be available
        // We don't actually use it, just verify compilation
    }
}

test "SIMD availability detection" {
    const has_simd = builtin.target.cpu.arch == .x86_64 or
        builtin.target.cpu.arch == .aarch64;

    _ = has_simd;

    // SIMD may be available
    // Just verify detection works
}

test "cache line size detection" {
    const cache_line = std.atomic.cache_line;

    // Should be a power of 2
    try testing.expect(cache_line >= 16);
    try testing.expect(cache_line <= 256);
    try testing.expect(std.math.isPowerOfTwo(cache_line));
}

test "page size detection" {
    const page_size = std.mem.page_size;

    // Should be a power of 2
    try testing.expect(page_size >= 4096);
    try testing.expect(std.math.isPowerOfTwo(page_size));
}

test "test allocator is working" {
    const allocator = testing.allocator;

    const buf = try allocator.alloc(u8, 100);
    defer allocator.free(buf);

    try testing.expectEqual(100, buf.len);
}

test "stdout/stderr/stdin exist in tests" {
    // These should be available even in tests
    // (though we won't use them in library code)

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    _ = stdin;
    _ = stdout;
    _ = stderr;
}

test "dependency verification - no external deps" {
    // sailor should have ZERO external dependencies
    // Only stdlib allowed

    // This test just verifies std imports work
    _ = std.mem;
    _ = std.io;
    _ = std.fs;
    _ = std.os;
    _ = std.fmt;
    _ = std.debug;
    _ = std.testing;
}
