const std = @import("std");

// Build steps:
//   zig build                           # Build library
//   zig build test                      # Run all tests
//   zig build benchmark                 # Run performance benchmarks
//   zig build example-hello             # Build hello example
//   zig build example-counter           # Build counter example
//   zig build example-dashboard         # Build dashboard example
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

    // Example applications
    const examples = [_]struct {
        name: []const u8,
        source: []const u8,
        description: []const u8,
    }{
        .{ .name = "hello", .source = "examples/hello.zig", .description = "Build and run hello example" },
        .{ .name = "counter", .source = "examples/counter.zig", .description = "Build and run counter example" },
        .{ .name = "dashboard", .source = "examples/dashboard.zig", .description = "Build and run dashboard example" },
        .{ .name = "task_list", .source = "examples/task_list.zig", .description = "Build and run task list example" },
    };

    inline for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.source),
                .target = target,
                .optimize = optimize,
            }),
        });

        exe.root_module.addImport("sailor", sailor_module);

        const install = b.addInstallArtifact(exe, .{});
        const step_name = b.fmt("example-{s}", .{example.name});
        const step = b.step(step_name, example.description);
        step.dependOn(&install.step);
    }
}
