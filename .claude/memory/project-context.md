✅ **Session 293** — FEATURE MODE (2026-06-12)
  - **Mode**: FEATURE (session 293, 293 % 5 == 3)
  - **Achievement**: Implemented v2.36.0 FilterBar Widget; tagged and released v2.36.0; established v2.37.0 milestone (TBD)

  **Completed Work**:
    - ✅ CI check: queued (not RED); 0 open GitHub issues
    - ✅ Implemented `src/tui/widgets/filter_bar.zig` — FilterBar: init(allocator); FilterTag (key, value, active: bool); addTag dupes strings; removeTag(index)/toggleTag(index)/clearAll() with memory freeing; activeCount()/tagCount(); withBlock/withTagStyle/withActiveStyle/withInactiveStyle/withPlaceholder builder API; render draws [key:value] pills horizontally, active in active_style, inactive in inactive_style, placeholder when empty
    - ✅ Implemented `tests/filter_bar_test.zig` — 77 comprehensive tests (TDD: test-writer then zig-developer)
    - ✅ Updated src/tui/tui.zig — exported FilterBar, FilterTag
    - ✅ Updated build.zig — added filter_bar_tests
    - ✅ All tests pass: `zig build test` exit code 0
    - ✅ Bumped version 2.35.0 → 2.36.0 in build.zig.zon
    - ✅ Tagged v2.36.0 on commit f2b6d30; GitHub release created
    - ✅ Consumer migration issues: zr#74, zoltraak#52, silica#63
    - ✅ Discord notification sent (Message ID: 1514975222867169290)
    - ✅ Commits: f2b6d30 feat(v2.36.0)

  **Current State**:
    - **Latest release**: v2.36.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Push triggered new run

  **Next Priority**:
    - Establish v2.37.0 milestone (new widget TBD — candidates: SplitPane, Timeline, or Minimap)
