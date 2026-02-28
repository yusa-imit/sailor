const std = @import("std");

// Build steps:
//   zig build                           # Build library
//   zig build test                      # Run all tests
//   zig build benchmark                 # Run performance benchmarks
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

    const cross_platform_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cross_platform_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const memory_safety_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/memory_safety_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const build_verification_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/build_verification_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);
    test_step.dependOn(&b.addRunArtifact(smoke_tests).step);
    test_step.dependOn(&b.addRunArtifact(cross_platform_tests).step);
    test_step.dependOn(&b.addRunArtifact(memory_safety_tests).step);
    test_step.dependOn(&b.addRunArtifact(build_verification_tests).step);

    // Benchmark executable
    const bench_exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/benchmark.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add sailor module to benchmark executable
    const sailor_module = b.createModule(.{
        .root_source_file = b.path("src/sailor.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_exe.root_module.addImport("sailor", sailor_module);

    const bench_install = b.addInstallArtifact(bench_exe, .{});
    const bench_step = b.step("benchmark", "Build and run performance benchmarks");
    bench_step.dependOn(&bench_install.step);

    const bench_run = b.addRunArtifact(bench_exe);
    bench_run.step.dependOn(&bench_install.step);
    bench_step.dependOn(&bench_run.step);
}
