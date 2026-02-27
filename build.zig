const std = @import("std");

// Build steps:
//   zig build                           # Build library
//   zig build test                      # Run all tests
//   zig build -Dtarget=x86_64-linux     # Cross-compile check

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module — consumed by other projects via build.zig.zon
    _ = b.addModule("sailor", .{
        .root_source_file = b.path("src/sailor.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unit tests — src module tests
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sailor.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Standalone tests in tests/ directory
    const smoke_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/smoke_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);
    test_step.dependOn(&b.addRunArtifact(smoke_tests).step);
}
