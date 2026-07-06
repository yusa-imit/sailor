✅ **Session 349** — FEATURE MODE (2026-07-06)
  - **Mode**: NORMAL (session 349, 349 % 5 == 4)
  - **Achievement**: Released v2.78.0 (RadialBar widget)

  **Completed Work**:
    - ✅ CI: queued (not RED); 0 open issues
    - ✅ Established v2.78.0 milestone: RadialBar widget
    - ✅ TDD Red: test-writer wrote 88 tests in tests/radial_bar_test.zig
    - ✅ TDD Green: zig-developer implemented src/tui/widgets/radial_bar.zig (454 lines)
    - ✅ Exports in tui.zig (radial_bar, RadialBar, RadialArc) and sailor.zig
    - ✅ All tests pass (exit 0)
    - ✅ Released v2.78.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#123, zoltraak#90, silica#101

  **Current State**:
    - **Latest release**: v2.78.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **Widget count**: 121 widgets in src/tui/widgets/ (radial_bar.zig added)
    - **CI**: triggered for v2.78.0 commit

  **RadialBar Widget Summary**:
    - RadialArc: label/value/style
    - RadialBar: arcs/focused/show_labels/show_values/style/arc_style/focused_style/label_style/empty_style/block
    - Concentric rings, outermost = arcs[0], innermost = last
    - Clockwise fill from 12 o'clock (top), remainder shows empty_style char
    - Terminal aspect ratio compensation (x*0.5 scaling for circular appearance)
    - Label/value column rendered to the right of the circle
    - MAX_ARCS=8, no heap allocations
    - 88 tests

  **Known Issue — Test Pattern**:
    - @floatFromInt in struct literal .{.value = @floatFromInt(i)} needs @as(f32, @floatFromInt(i)) in Zig 0.15.x
    - Future test-writers must use explicit type annotation in struct literal contexts

  **Next Priority**:
    - Establish v2.79.0 milestone (candidates: StreamGraph, ViolinPlot, SunburstChart)

✅ **Session 348** — FEATURE MODE (2026-07-06)
  - **Mode**: NORMAL (session 348, 348 % 5 == 3)
  - **Achievement**: Released v2.77.0 (DotPlot widget)

  **Completed Work**:
    - ✅ CI: queued (not RED); 0 open issues
    - ✅ Established v2.77.0 milestone: DotPlot widget
    - ✅ TDD Red: test-writer wrote 94 tests in tests/dot_plot_test.zig
    - ✅ Fixed 10 @floatFromInt type-inference errors in test file (Zig 0.15.x struct literal issue)
    - ✅ TDD Green: zig-developer implemented src/tui/widgets/dot_plot.zig (320 lines)
    - ✅ Exports in tui.zig (dot_plot, DotPlot, DotPlotItem) and sailor.zig
    - ✅ All tests pass (exit 0)
    - ✅ Released v2.77.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#122, zoltraak#89, silica#100

  **Current State**:
    - **Latest release**: v2.77.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **Widget count**: 120 widgets in src/tui/widgets/ (dot_plot.zig added)
    - **CI**: triggered for v2.77.0 commit

  **DotPlot Widget Summary**:
    - DotPlotItem: label/value/style
    - DotPlot: items/focused/x_min/x_max/show_labels/show_values/dot_char/style/dot_style/focused_style/label_style/line_style/block
    - Label column auto-sized to min(max_label_len, inner_width/3)
    - Dashed line (─) from label to dot position
    - Dot placed at normalized x: (value - x_min) / (x_max - x_min) * (plot_width - 1)
    - Focused item uses focused_style on dot cell
    - MAX_ITEMS=64, no heap allocations
    - 94 tests

  **Known Issue — Test Pattern**:
    - @floatFromInt(i) in struct literal .{.value = @floatFromInt(i)} needs @as(f32, @floatFromInt(i)) in Zig 0.15.x
    - Future test-writers must use explicit type annotation in struct literal contexts

  **Next Priority**:
    - Establish v2.78.0 milestone (candidates: StreamGraph, ViolinPlot, RadialBar)

✅ **Session 347** — FEATURE MODE (2026-07-06)
  - **Mode**: NORMAL (session 347, 347 % 5 == 2)
  - **Achievement**: Released v2.76.0 (FunnelChart widget)

  **Completed Work**:
    - ✅ CI: queued (not RED); 0 open issues
    - ✅ Established v2.76.0 milestone: FunnelChart widget
    - ✅ TDD Red: test-writer wrote 89 tests in tests/funnel_chart_test.zig
    - ✅ TDD Green: zig-developer implemented src/tui/widgets/funnel_chart.zig (339 lines)
    - ✅ Exports in tui.zig (funnel_chart, FunnelChart, FunnelStage) and sailor.zig
    - ✅ All tests pass (exit 0)
    - ✅ Released v2.76.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#121, zoltraak#88, silica#99

  **FunnelChart Widget Summary**:
    - FunnelStage: label/value/style
    - FunnelChart: stages/focused/style/label_style/value_style/focused_style/show_values/show_percentages/block
    - Centered bars proportional to stage.value/maxValue; stages narrow top-to-bottom
    - Optional value and percentage labels
    - MAX_STAGES=16, no heap allocations
    - 89 tests

✅ **Session 346** — FEATURE MODE (2026-07-06)
  - **Mode**: NORMAL (session 346, 346 % 5 == 1)
  - **Achievement**: Fixed CI red + Released v2.75.0 (WaterfallChart widget)

  **Completed Work**:
    - ✅ CI was RED: macos-latest now resolves to macOS 26 (Tahoe); Zig 0.15.2 can't link (undefined libc symbols)
    - ✅ Fixed: pinned ARM64 runner to macos-15 in ci.yml; committed 4c51a84
    - ✅ Established v2.75.0 milestone: WaterfallChart widget
    - ✅ TDD Red: test-writer wrote 90 tests in tests/waterfall_chart_test.zig
    - ✅ TDD Green: zig-developer implemented src/tui/widgets/waterfall_chart.zig (410 lines)
    - ✅ Exports in tui.zig (waterfall_chart, WaterfallChart, WaterfallBar, WaterfallKind) and sailor.zig
    - ✅ All tests pass (exit 0)
    - ✅ Released v2.75.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#120, zoltraak#87, silica#98

  **WaterfallChart Widget Summary**:
    - WaterfallKind: .relative (cumulative delta), .absolute (reset baseline), .total (show running total)
    - WaterfallBar: label/value/kind/style
    - WaterfallChart: bars/focused/show_values/show_connectors/positive_style/negative_style/total_style/focused_style/connector_style/style/block
    - MAX_BARS=32, no heap allocations
    - 90 tests
