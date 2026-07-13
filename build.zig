const std = @import("std");

// Build steps:
//   zig build                                        # Build library
//   zig build test                                   # Run all tests
//   zig build benchmark                              # Run performance benchmarks
//   zig build example-hello                          # Build hello example
//   zig build example-counter                        # Build counter example
//   zig build example-dashboard                      # Build dashboard example
//   zig build -Dtarget=x86_64-linux                  # Cross-compile check
//   zig build -Ddeprecation-mode=error               # Treat deprecations as errors
//   zig build -Ddeprecation-mode=ignore              # Suppress deprecation warnings

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Deprecation mode option: warn (default), error, or ignore
    const deprecation_mode = b.option(
        []const u8,
        "deprecation-mode",
        "How to handle deprecation warnings: 'warn' (default), 'error', or 'ignore'",
    ) orelse "warn";

    // Build options for comptime configuration
    const options = b.addOptions();
    options.addOption([]const u8, "deprecation_mode", deprecation_mode);

    // Library module — consumed by other projects via build.zig.zon
    const sailor_module = b.addModule("sailor", .{
        .root_source_file = b.path("src/sailor.zig"),
        .target = target,
        .optimize = optimize,
    });
    sailor_module.addImport("build_options", options.createModule());

    // Unit tests — src module tests
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sailor.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib_tests.root_module.addImport("build_options", options.createModule());
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

    // NOTE: Old inspector_tests disabled - replaced by v2.9.0 WidgetInspector API
    // Tests are now in src/tui/inspector.zig itself
    // const inspector_tests = b.addTest(.{
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("tests/inspector_test.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //     }),
    // });

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

    const theme_loader_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/theme_loader_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const widget_helpers_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/widget_helpers_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const plugin_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/plugin_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const animation_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/animation_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const transition_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/transition_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const timer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/timer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const event_metrics_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/event_metrics_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const metrics_dashboard_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/metrics_dashboard_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const widget_lifecycle_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/widget_lifecycle_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const grapheme_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/grapheme_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const validation_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/validation_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const eventbus_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/eventbus_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const platform_opts_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/platform_opts_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const advanced_profiler_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/advanced_profiler_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const error_recovery_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/error_recovery_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const developer_console_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/developer_console_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const llm_client_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/llm_client_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const smart_autocomplete_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/smart_autocomplete_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const layout_intelligence_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/layout_intelligence_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const natural_language_commands_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/natural_language_commands_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const sixel_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/sixel_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // TODO: Re-enable migration tests after updating for v2.0.0 scope
    // (removed Color/Constraint simplification patterns)
    // const migration_script_tests = b.addTest(.{
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("tests/migration_script_test.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //     }),
    // });

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
    // inspector_tests.root_module.addImport("sailor", sailor_module_for_tests); // disabled
    docgen_tests.root_module.addImport("sailor", sailor_module_for_tests);
    arg_groups_tests.root_module.addImport("sailor", sailor_module_for_tests);
    color_theme_tests.root_module.addImport("sailor", sailor_module_for_tests);
    env_config_tests.root_module.addImport("sailor", sailor_module_for_tests);
    windows_unicode_tests.root_module.addImport("sailor", sailor_module_for_tests);
    chunkedbuffer_tests.root_module.addImport("sailor", sailor_module_for_tests);
    span_builder_tests.root_module.addImport("sailor", sailor_module_for_tests);
    richtext_parser_tests.root_module.addImport("sailor", sailor_module_for_tests);
    theme_loader_tests.root_module.addImport("sailor", sailor_module_for_tests);
    widget_helpers_tests.root_module.addImport("sailor", sailor_module_for_tests);
    plugin_tests.root_module.addImport("sailor", sailor_module_for_tests);
    animation_tests.root_module.addImport("sailor", sailor_module_for_tests);
    transition_tests.root_module.addImport("sailor", sailor_module_for_tests);
    timer_tests.root_module.addImport("sailor", sailor_module_for_tests);
    event_metrics_tests.root_module.addImport("sailor", sailor_module_for_tests);
    metrics_dashboard_tests.root_module.addImport("sailor", sailor_module_for_tests);
    widget_lifecycle_tests.root_module.addImport("sailor", sailor_module_for_tests);
    grapheme_tests.root_module.addImport("sailor", sailor_module_for_tests);
    validation_tests.root_module.addImport("sailor", sailor_module_for_tests);
    eventbus_tests.root_module.addImport("sailor", sailor_module_for_tests);
    platform_opts_tests.root_module.addImport("sailor", sailor_module_for_tests);
    advanced_profiler_tests.root_module.addImport("sailor", sailor_module_for_tests);
    error_recovery_tests.root_module.addImport("sailor", sailor_module_for_tests);
    developer_console_tests.root_module.addImport("sailor", sailor_module_for_tests);
    llm_client_tests.root_module.addImport("sailor", sailor_module_for_tests);
    smart_autocomplete_tests.root_module.addImport("sailor", sailor_module_for_tests);
    layout_intelligence_tests.root_module.addImport("sailor", sailor_module_for_tests);
    natural_language_commands_tests.root_module.addImport("sailor", sailor_module_for_tests);
    sixel_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const kitty_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/kitty_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    kitty_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const ansi_art_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ansi_art_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ansi_art_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const particles_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/particles_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    particles_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const symbols_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/symbols_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    symbols_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const adaptive_renderer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/adaptive_renderer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    adaptive_renderer_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const signal_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/signal_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    signal_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const store_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/store_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    store_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const reactive_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/reactive_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    reactive_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const middleware_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/middleware_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    middleware_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const thunk_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/thunk_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    thunk_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const undo_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/undo_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    undo_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const persist_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/persist_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    persist_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const reactive_list_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/reactive_list_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    reactive_list_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const fuzzy_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzzy_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    fuzzy_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const command_palette_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/command_palette_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    command_palette_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const filterable_list_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/filterable_list_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    filterable_list_tests.root_module.addImport("sailor", sailor_module_for_tests);

    const pager_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/pager_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pager_tests.root_module.addImport("sailor", sailor_module_for_tests);

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
    // test_step.dependOn(&b.addRunArtifact(inspector_tests).step); // disabled
    test_step.dependOn(&b.addRunArtifact(docgen_tests).step);
    test_step.dependOn(&b.addRunArtifact(arg_groups_tests).step);
    test_step.dependOn(&b.addRunArtifact(color_theme_tests).step);
    test_step.dependOn(&b.addRunArtifact(env_config_tests).step);
    test_step.dependOn(&b.addRunArtifact(windows_unicode_tests).step);
    test_step.dependOn(&b.addRunArtifact(chunkedbuffer_tests).step);
    test_step.dependOn(&b.addRunArtifact(span_builder_tests).step);
    test_step.dependOn(&b.addRunArtifact(richtext_parser_tests).step);
    test_step.dependOn(&b.addRunArtifact(theme_loader_tests).step);
    test_step.dependOn(&b.addRunArtifact(widget_helpers_tests).step);
    test_step.dependOn(&b.addRunArtifact(plugin_tests).step);
    test_step.dependOn(&b.addRunArtifact(animation_tests).step);
    test_step.dependOn(&b.addRunArtifact(transition_tests).step);
    test_step.dependOn(&b.addRunArtifact(timer_tests).step);
    test_step.dependOn(&b.addRunArtifact(event_metrics_tests).step);
    test_step.dependOn(&b.addRunArtifact(metrics_dashboard_tests).step);
    test_step.dependOn(&b.addRunArtifact(widget_lifecycle_tests).step);
    test_step.dependOn(&b.addRunArtifact(grapheme_tests).step);
    test_step.dependOn(&b.addRunArtifact(validation_tests).step);
    test_step.dependOn(&b.addRunArtifact(eventbus_tests).step);
    test_step.dependOn(&b.addRunArtifact(platform_opts_tests).step);
    test_step.dependOn(&b.addRunArtifact(advanced_profiler_tests).step);
    test_step.dependOn(&b.addRunArtifact(error_recovery_tests).step);
    test_step.dependOn(&b.addRunArtifact(developer_console_tests).step);
    test_step.dependOn(&b.addRunArtifact(llm_client_tests).step);
    test_step.dependOn(&b.addRunArtifact(smart_autocomplete_tests).step);
    test_step.dependOn(&b.addRunArtifact(layout_intelligence_tests).step);
    test_step.dependOn(&b.addRunArtifact(natural_language_commands_tests).step);
    test_step.dependOn(&b.addRunArtifact(sixel_tests).step);
    test_step.dependOn(&b.addRunArtifact(kitty_tests).step);
    test_step.dependOn(&b.addRunArtifact(ansi_art_tests).step);
    test_step.dependOn(&b.addRunArtifact(particles_tests).step);
    test_step.dependOn(&b.addRunArtifact(symbols_tests).step);
    test_step.dependOn(&b.addRunArtifact(adaptive_renderer_tests).step);
    test_step.dependOn(&b.addRunArtifact(signal_tests).step);
    test_step.dependOn(&b.addRunArtifact(store_tests).step);
    test_step.dependOn(&b.addRunArtifact(reactive_tests).step);
    test_step.dependOn(&b.addRunArtifact(middleware_tests).step);
    test_step.dependOn(&b.addRunArtifact(thunk_tests).step);
    test_step.dependOn(&b.addRunArtifact(undo_tests).step);
    test_step.dependOn(&b.addRunArtifact(persist_tests).step);
    test_step.dependOn(&b.addRunArtifact(reactive_list_tests).step);
    test_step.dependOn(&b.addRunArtifact(fuzzy_tests).step);
    test_step.dependOn(&b.addRunArtifact(command_palette_tests).step);
    test_step.dependOn(&b.addRunArtifact(filterable_list_tests).step);
    test_step.dependOn(&b.addRunArtifact(pager_tests).step);

    const dag_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/dag_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    dag_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(dag_tests).step);

    const pipeline_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/pipeline_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pipeline_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(pipeline_tests).step);

    const diff_viewer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/diff_viewer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    diff_viewer_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(diff_viewer_tests).step);

    const json_browser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/json_browser_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    json_browser_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(json_browser_tests).step);

    const editable_table_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/editable_table_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    editable_table_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(editable_table_tests).step);

    const record_editor_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/record_editor_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    record_editor_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(record_editor_tests).step);
    // test_step.dependOn(&b.addRunArtifact(migration_script_tests).step); // Disabled for v2.0.0 work

    const layout_template_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/layout_template_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    layout_template_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(layout_template_tests).step);

    const stepper_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/stepper_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    stepper_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(stepper_tests).step);

    const scrollbar_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/scrollbar_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    scrollbar_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(scrollbar_tests).step);

    const breadcrumb_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/breadcrumb_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    breadcrumb_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(breadcrumb_tests).step);

    const screen_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/screen_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    screen_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(screen_tests).step);

    const router_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/router_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    router_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(router_tests).step);

    const app_shell_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/app_shell_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    app_shell_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(app_shell_tests).step);

    const keybinding_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/keybinding_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    keybinding_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(keybinding_tests).step);

    const statusline_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/statusline_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    statusline_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(statusline_tests).step);

    const workspace_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/workspace_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    workspace_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(workspace_tests).step);

    const form_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/form_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    form_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(form_tests).step);

    const multi_select_list_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/multi_select_list_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    multi_select_list_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(multi_select_list_tests).step);

    const reorderable_list_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/reorderable_list_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    reorderable_list_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(reorderable_list_tests).step);

    const select_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/select_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    select_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(select_tests).step);

    const color_picker_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/color_picker_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    color_picker_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(color_picker_tests).step);

    const context_menu_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/context_menu_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    context_menu_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(context_menu_tests).step);

    const toast_manager_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/toast_manager_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    toast_manager_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(toast_manager_tests).step);

    const accordion_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/accordion_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    accordion_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(accordion_tests).step);

    const timeline_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/timeline_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    timeline_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(timeline_tests).step);

    const command_bar_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/command_bar_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    command_bar_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(command_bar_tests).step);

    const inspector_tests = b.addTest(.{
        .name = "inspector_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/inspector_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    inspector_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(inspector_tests).step);

    const status_grid_tests = b.addTest(.{
        .name = "status_grid_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/status_grid_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    status_grid_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(status_grid_tests).step);

    const log_viewer_tests = b.addTest(.{
        .name = "log_viewer_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/log_viewer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    log_viewer_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(log_viewer_tests).step);

    const filter_bar_tests = b.addTest(.{
        .name = "filter_bar_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/filter_bar_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    filter_bar_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(filter_bar_tests).step);

    const pagination_tests = b.addTest(.{
        .name = "pagination_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/pagination_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pagination_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(pagination_tests).step);

    const keymap_tests = b.addTest(.{
        .name = "keymap_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/keymap_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    keymap_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(keymap_tests).step);

    const numberinput_tests = b.addTest(.{
        .name = "numberinput_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/numberinput_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    numberinput_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(numberinput_tests).step);

    const rangeslider_tests = b.addTest(.{
        .name = "rangeslider_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/rangeslider_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    rangeslider_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(rangeslider_tests).step);

    const colorswatch_tests = b.addTest(.{
        .name = "colorswatch_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/colorswatch_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    colorswatch_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(colorswatch_tests).step);

    const treetable_tests = b.addTest(.{
        .name = "treetable_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/treetable_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    treetable_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(treetable_tests).step);

    const virtualtable_tests = b.addTest(.{
        .name = "virtualtable_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/virtualtable_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    virtualtable_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(virtualtable_tests).step);

    const hexviewer_tests = b.addTest(.{
        .name = "hexviewer_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/hexviewer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hexviewer_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(hexviewer_tests).step);

    const keyvalue_viewer_tests = b.addTest(.{
        .name = "keyvalue_viewer_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/keyvalue_viewer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    keyvalue_viewer_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(keyvalue_viewer_tests).step);

    const paragraph_tests = b.addTest(.{
        .name = "paragraph_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/paragraph_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    paragraph_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(paragraph_tests).step);

    const list_tests = b.addTest(.{
        .name = "list_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/list_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    list_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(list_tests).step);

    const input_tests = b.addTest(.{
        .name = "input_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/input_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    input_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(input_tests).step);

    const tabs_tests = b.addTest(.{
        .name = "tabs_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/tabs_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tabs_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(tabs_tests).step);

    const gauge_tests = b.addTest(.{
        .name = "gauge_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gauge_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    gauge_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(gauge_tests).step);

    const spinner_tests = b.addTest(.{
        .name = "spinner_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/spinner_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    spinner_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(spinner_tests).step);

    const diffstat_tests = b.addTest(.{
        .name = "diffstat_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/diffstat_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    diffstat_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(diffstat_tests).step);

    const marquee_tests = b.addTest(.{
        .name = "marquee_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/marquee_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    marquee_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(marquee_tests).step);

    const wizard_tests = b.addTest(.{
        .name = "wizard_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/wizard_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    wizard_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(wizard_tests).step);

    const carousel_tests = b.addTest(.{
        .name = "carousel_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/carousel_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    carousel_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(carousel_tests).step);

    const countdown_timer_tests = b.addTest(.{
        .name = "countdown_timer_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/countdown_timer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    countdown_timer_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(countdown_timer_tests).step);

    const animated_border_tests = b.addTest(.{
        .name = "animated_border_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/animated_border_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    animated_border_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(animated_border_tests).step);

    const progress_ring_tests = b.addTest(.{
        .name = "progress_ring_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/progress_ring_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    progress_ring_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(progress_ring_tests).step);

    const animated_text_tests = b.addTest(.{
        .name = "animated_text_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/animated_text_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    animated_text_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(animated_text_tests).step);

    const flow_text_tests = b.addTest(.{
        .name = "flow_text_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/flow_text_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    flow_text_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(flow_text_tests).step);

    const minimap_tests = b.addTest(.{
        .name = "minimap_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/minimap_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    minimap_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(minimap_tests).step);

    const ring_menu_tests = b.addTest(.{
        .name = "ring_menu_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ring_menu_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ring_menu_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(ring_menu_tests).step);

    const split_text_tests = b.addTest(.{
        .name = "split_text_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/split_text_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    split_text_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(split_text_tests).step);

    const stopwatch_tests = b.addTest(.{
        .name = "stopwatch_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/stopwatch_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    stopwatch_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(stopwatch_tests).step);

    const wordcloud_tests = b.addTest(.{
        .name = "wordcloud_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/wordcloud_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    wordcloud_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(wordcloud_tests).step);

    const kanban_tests = b.addTest(.{
        .name = "kanban_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/kanban_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    kanban_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(kanban_tests).step);

    const bracket_viewer_tests = b.addTest(.{
        .name = "bracket_viewer_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/bracket_viewer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bracket_viewer_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(bracket_viewer_tests).step);

    const activity_feed_tests = b.addTest(.{
        .name = "activity_feed_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/activity_feed_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    activity_feed_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(activity_feed_tests).step);

    const gantt_tests = b.addTest(.{
        .name = "gantt_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gantt_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    gantt_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(gantt_tests).step);

    const flowchart_tests = b.addTest(.{
        .name = "flowchart_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/flowchart_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    flowchart_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(flowchart_tests).step);

    const mindmap_tests = b.addTest(.{
        .name = "mindmap_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/mindmap_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    mindmap_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(mindmap_tests).step);

    const radar_chart_tests = b.addTest(.{
        .name = "radar_chart_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/radar_chart_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    radar_chart_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(radar_chart_tests).step);

    const hex_editor_tests = b.addTest(.{
        .name = "hex_editor_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/hex_editor_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hex_editor_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(hex_editor_tests).step);

    const treemap_tests = b.addTest(.{
        .name = "treemap_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/treemap_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    treemap_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(treemap_tests).step);

    const matrix_view_tests = b.addTest(.{
        .name = "matrix_view_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/matrix_view_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    matrix_view_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(matrix_view_tests).step);

    const sankey_tests = b.addTest(.{
        .name = "sankey_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/sankey_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sankey_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(sankey_tests).step);

    const gantt_chart_tests = b.addTest(.{
        .name = "gantt_chart_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gantt_chart_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    gantt_chart_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(gantt_chart_tests).step);

    const bubble_chart_tests = b.addTest(.{
        .name = "bubble_chart_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/bubble_chart_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bubble_chart_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(bubble_chart_tests).step);

    const chord_diagram_tests = b.addTest(.{
        .name = "chord_diagram_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/chord_diagram_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    chord_diagram_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(chord_diagram_tests).step);

    const waterfall_chart_tests = b.addTest(.{
        .name = "waterfall_chart_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/waterfall_chart_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    waterfall_chart_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(waterfall_chart_tests).step);

    const funnel_chart_tests = b.addTest(.{
        .name = "funnel_chart_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/funnel_chart_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    funnel_chart_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(funnel_chart_tests).step);

    const dot_plot_tests = b.addTest(.{
        .name = "dot_plot_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/dot_plot_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    dot_plot_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(dot_plot_tests).step);

    const radial_bar_tests = b.addTest(.{
        .name = "radial_bar_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/radial_bar_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    radial_bar_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(radial_bar_tests).step);

    const sunburst_chart_tests = b.addTest(.{
        .name = "sunburst_chart_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/sunburst_chart_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sunburst_chart_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(sunburst_chart_tests).step);

    const stream_graph_tests = b.addTest(.{
        .name = "stream_graph_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/stream_graph_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    stream_graph_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(stream_graph_tests).step);

    const violin_plot_tests = b.addTest(.{
        .name = "violin_plot_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/violin_plot_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    violin_plot_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(violin_plot_tests).step);

    const box_plot_tests = b.addTest(.{
        .name = "box_plot_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/box_plot_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    box_plot_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(box_plot_tests).step);

    const candlestick_chart_tests = b.addTest(.{
        .name = "candlestick_chart_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/candlestick_chart_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    candlestick_chart_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(candlestick_chart_tests).step);

    const bullet_chart_tests = b.addTest(.{
        .name = "bullet_chart_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/bullet_chart_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bullet_chart_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(bullet_chart_tests).step);

    const parallel_coordinates_tests = b.addTest(.{
        .name = "parallel_coordinates_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/parallel_coordinates_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    parallel_coordinates_tests.root_module.addImport("sailor", sailor_module_for_tests);
    test_step.dependOn(&b.addRunArtifact(parallel_coordinates_tests).step);

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
        .{ .name = "dashboard-advanced", .source = "examples/dashboard_advanced.zig", .description = "Build and run advanced dashboard (v1.32.0 features: nested grids, aspect ratios, margins, debugging)" },
        .{ .name = "task_list", .source = "examples/task_list.zig", .description = "Build and run task list example" },
        .{ .name = "layout_showcase", .source = "examples/layout_showcase.zig", .description = "Build and run layout showcase (v1.2.0 features)" },
        .{ .name = "widget_gallery", .source = "examples/widget_gallery.zig", .description = "Interactive widget gallery with code examples (v1.18.0)" },
        .{ .name = "plugin_demo", .source = "examples/plugin_demo.zig", .description = "Plugin architecture demo — custom widgets & composition (v1.23.0)" },
        .{ .name = "animation_demo", .source = "examples/animation_demo.zig", .description = "Animation & transitions demo — easing functions, timers, color animation (v1.24.0)" },
        .{ .name = "form_demo", .source = "examples/form_demo.zig", .description = "Form & validation demo — registration/login with validators (v1.25.0)" },
        .{ .name = "error_handling", .source = "examples/error_handling_demo.zig", .description = "Error handling demo — structured errors, debug logging, recovery strategies (v1.30.0)" },
        .{ .name = "profile_demo", .source = "examples/profile_demo.zig", .description = "Profiling demo — render profiler, memory tracker, event loop profiler, widget metrics (v1.31.0)" },
        .{ .name = "accessibility_demo", .source = "examples/accessibility_demo.zig", .description = "Accessibility demo — tab navigation, focus management, disabled widgets, keyboard navigation (v1.35.0)" },
        .{ .name = "metrics_dashboard", .source = "examples/metrics_dashboard.zig", .description = "Performance metrics dashboard — render/memory/event monitoring, 3 layout modes (v1.36.0)" },
        .{ .name = "migration_demo", .source = "examples/migration_demo.zig", .description = "Migration demo — v1.x to v2.0.0 API side-by-side comparison (v1.37.0)" },
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
