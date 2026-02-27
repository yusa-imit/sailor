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

    // Unit tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sailor.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
