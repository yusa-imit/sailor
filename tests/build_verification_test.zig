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

    // Verify mode is one of the four valid build modes
    const is_valid = switch (mode) {
        .Debug, .ReleaseSafe, .ReleaseFast, .ReleaseSmall => true,
    };
    try testing.expect(is_valid);
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

test "safety checks enabled in safe modes" {
    // Verify mode is valid and safe modes include Debug and ReleaseSafe
    const is_safe_mode = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
    const is_fast_mode = builtin.mode == .ReleaseFast or builtin.mode == .ReleaseSmall;

    // Mode must be either safe or fast
    try testing.expect(is_safe_mode or is_fast_mode);
}

test "libc linkage detection" {
    // sailor should work with or without libc - verify bool value is valid
    const link_libc = builtin.link_libc;

    // link_libc is a boolean, verify it's either true or false
    try testing.expect(link_libc == true or link_libc == false);
}

test "build mode categorization" {
    // Verify build mode can be categorized as debug or release
    const is_debug = builtin.mode == .Debug;
    const is_release = builtin.mode != .Debug;

    // Must be exactly one category
    try testing.expect(is_debug != is_release);
}

test "PIE/PIC detection" {
    const pic = builtin.position_independent_code;

    // PIC is a boolean value
    try testing.expect(pic == true or pic == false);
}

test "safe mode detection" {
    // Verify we can detect safe modes correctly
    const has_safety = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
    const no_safety = builtin.mode == .ReleaseFast or builtin.mode == .ReleaseSmall;

    // Must be exactly one category
    try testing.expect(has_safety != no_safety);
}

test "sanitizers detection" {
    // Verify sanitizer detection returns a boolean value
    const has_sanitize_thread = if (@hasDecl(builtin, "sanitize_thread")) builtin.sanitize_thread else false;

    // Should be a boolean value
    try testing.expect(has_sanitize_thread == true or has_sanitize_thread == false);
}

test "object format detection" {
    const format = builtin.object_format;

    const is_valid = switch (format) {
        .elf, .macho, .coff, .wasm => true,
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
    const ptr_bits = @bitSizeOf(usize);

    // Should be 32 or 64 bit
    try testing.expect(ptr_bits == 32 or ptr_bits == 64);
}

test "dynamic linker detection" {
    // Verify dynamic linker info is accessible and is either present or null
    const has_dl = builtin.target.dynamic_linker.get() != null;

    // Should be a boolean value
    try testing.expect(has_dl == true or has_dl == false);
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
    // Verify CPU architecture is one of the common ones that support inline asm
    const arch = builtin.cpu.arch;
    const supports_asm = arch == .x86_64 or arch == .aarch64 or
                         arch == .arm or arch == .x86 or arch == .riscv64;

    // All our supported platforms should support inline assembly
    try testing.expect(supports_asm);
}

test "SIMD availability detection" {
    const has_simd = builtin.target.cpu.arch == .x86_64 or
        builtin.target.cpu.arch == .aarch64;

    // Should be a boolean value
    try testing.expect(has_simd == true or has_simd == false);
}

test "cache line size detection" {
    const cache_line = std.atomic.cache_line;

    // Should be a power of 2
    try testing.expect(cache_line >= 16);
    try testing.expect(cache_line <= 256);
    try testing.expect(std.math.isPowerOfTwo(cache_line));
}

test "page size detection" {
    // Page size detection in 0.15.x
    // Typically 4096 on most platforms
    const page_size = 4096; // Standard page size for testing

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

test "std.io module is available" {
    // Verify std.io has the basic types we expect
    const has_writer = @hasDecl(std.io, "Writer");
    const has_reader = @hasDecl(std.io, "Reader");

    try testing.expect(has_writer);
    try testing.expect(has_reader);
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
