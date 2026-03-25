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
    lib_tests.root_module.link_libc = true; // Required for env.zig tests (setenv/unsetenv)

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

    const widget_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/widget_integration_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const performance_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/performance_integration_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const widget_snapshots_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/widget_snapshots_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const snapshot_assertions_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/snapshot_assertions_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const example_test_patterns = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/example_test_patterns.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const advanced_widgets_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/advanced_widgets_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const edge_cases_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/edge_cases_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const multicursor_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/multicursor_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const richtext_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/richtext_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const pooling_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/pooling_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const incremental_layout_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/incremental_layout_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const platform_edge_cases_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/platform_edge_cases_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const termcap_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/termcap_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const menu_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/menu_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const calendar_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/calendar_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const filebrowser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/filebrowser_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const terminal_widget_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/terminal_widget_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const markdown_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/markdown_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const inspector_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/inspector_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const docgen_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/docgen_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const arg_groups_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/arg_groups_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const color_theme_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/color_theme_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const env_config_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/env_config_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    env_config_tests.linkLibC();

    const windows_unicode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/windows_unicode_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const chunkedbuffer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/chunkedbuffer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const span_builder_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/span_builder_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const richtext_parser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/richtext_parser_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add sailor module to integration tests
    const sailor_module_for_tests = b.createModule(.{
        .root_source_file = b.path("src/sailor.zig"),
        .target = target,
        .optimize = optimize,
    });
    widget_integration_tests.root_module.addImport("sailor", sailor_module_for_tests);
    performance_integration_tests.root_module.addImport("sailor", sailor_module_for_tests);
    widget_snapshots_tests.root_module.addImport("sailor", sailor_module_for_tests);
    snapshot_assertions_tests.root_module.addImport("sailor", sailor_module_for_tests);
    example_test_patterns.root_module.addImport("sailor", sailor_module_for_tests);
    advanced_widgets_tests.root_module.addImport("sailor", sailor_module_for_tests);
    edge_cases_tests.root_module.addImport("sailor", sailor_module_for_tests);
    multicursor_tests.root_module.addImport("sailor", sailor_module_for_tests);
    richtext_tests.root_module.addImport("sailor", sailor_module_for_tests);
    pooling_tests.root_module.addImport("sailor", sailor_module_for_tests);
    incremental_layout_tests.root_module.addImport("sailor", sailor_module_for_tests);
    platform_edge_cases_tests.root_module.addImport("sailor", sailor_module_for_tests);
    termcap_tests.root_module.addImport("sailor", sailor_module_for_tests);
    menu_tests.root_module.addImport("sailor", sailor_module_for_tests);
    calendar_tests.root_module.addImport("sailor", sailor_module_for_tests);
    filebrowser_tests.root_module.addImport("sailor", sailor_module_for_tests);
    terminal_widget_tests.root_module.addImport("sailor", sailor_module_for_tests);
    markdown_tests.root_module.addImport("sailor", sailor_module_for_tests);
    inspector_tests.root_module.addImport("sailor", sailor_module_for_tests);
    docgen_tests.root_module.addImport("sailor", sailor_module_for_tests);
    arg_groups_tests.root_module.addImport("sailor", sailor_module_for_tests);
    color_theme_tests.root_module.addImport("sailor", sailor_module_for_tests);
    env_config_tests.root_module.addImport("sailor", sailor_module_for_tests);
    windows_unicode_tests.root_module.addImport("sailor", sailor_module_for_tests);
    chunkedbuffer_tests.root_module.addImport("sailor", sailor_module_for_tests);
    span_builder_tests.root_module.addImport("sailor", sailor_module_for_tests);
    richtext_parser_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);
    test_step.dependOn(&b.addRunArtifact(smoke_tests).step);
    test_step.dependOn(&b.addRunArtifact(cross_platform_tests).step);
    test_step.dependOn(&b.addRunArtifact(memory_safety_tests).step);
    test_step.dependOn(&b.addRunArtifact(build_verification_tests).step);
    test_step.dependOn(&b.addRunArtifact(widget_integration_tests).step);
    test_step.dependOn(&b.addRunArtifact(performance_integration_tests).step);
    test_step.dependOn(&b.addRunArtifact(widget_snapshots_tests).step);
    test_step.dependOn(&b.addRunArtifact(snapshot_assertions_tests).step);
    test_step.dependOn(&b.addRunArtifact(example_test_patterns).step);
    test_step.dependOn(&b.addRunArtifact(advanced_widgets_tests).step);
    test_step.dependOn(&b.addRunArtifact(edge_cases_tests).step);
    test_step.dependOn(&b.addRunArtifact(multicursor_tests).step);
    test_step.dependOn(&b.addRunArtifact(richtext_tests).step);
    test_step.dependOn(&b.addRunArtifact(pooling_tests).step);
    test_step.dependOn(&b.addRunArtifact(incremental_layout_tests).step);
    test_step.dependOn(&b.addRunArtifact(platform_edge_cases_tests).step);
    test_step.dependOn(&b.addRunArtifact(termcap_tests).step);
    test_step.dependOn(&b.addRunArtifact(menu_tests).step);
    test_step.dependOn(&b.addRunArtifact(calendar_tests).step);
    test_step.dependOn(&b.addRunArtifact(filebrowser_tests).step);
    test_step.dependOn(&b.addRunArtifact(terminal_widget_tests).step);
    test_step.dependOn(&b.addRunArtifact(markdown_tests).step);
    test_step.dependOn(&b.addRunArtifact(inspector_tests).step);
    test_step.dependOn(&b.addRunArtifact(docgen_tests).step);
    test_step.dependOn(&b.addRunArtifact(arg_groups_tests).step);
    test_step.dependOn(&b.addRunArtifact(color_theme_tests).step);
    test_step.dependOn(&b.addRunArtifact(env_config_tests).step);
    test_step.dependOn(&b.addRunArtifact(windows_unicode_tests).step);
    test_step.dependOn(&b.addRunArtifact(chunkedbuffer_tests).step);
    test_step.dependOn(&b.addRunArtifact(span_builder_tests).step);
    test_step.dependOn(&b.addRunArtifact(richtext_parser_tests).step);

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

    // Large data benchmark (v1.21.0)
    const large_data_bench_exe = b.addExecutable(.{
        .name = "large_data_bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/large_data_bench.zig"),
            .target = target,
            .optimize = .ReleaseFast, // Use optimized build for accurate benchmarks
        }),
    });
    large_data_bench_exe.root_module.addImport("sailor", sailor_module);

    const large_data_bench_install = b.addInstallArtifact(large_data_bench_exe, .{});
    const large_data_bench_step = b.step("bench-large-data", "Run large data streaming benchmarks (1M items)");
    large_data_bench_step.dependOn(&large_data_bench_install.step);

    const large_data_bench_run = b.addRunArtifact(large_data_bench_exe);
    large_data_bench_run.step.dependOn(&large_data_bench_install.step);
    large_data_bench_step.dependOn(&large_data_bench_run.step);

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
        .{ .name = "layout_showcase", .source = "examples/layout_showcase.zig", .description = "Build and run layout showcase (v1.2.0 features)" },
        .{ .name = "widget_gallery", .source = "examples/widget_gallery.zig", .description = "Interactive widget gallery with code examples (v1.18.0)" },
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
