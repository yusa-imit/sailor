✅ **Session 311** — FEATURE MODE (2026-06-20)
  - **Mode**: NORMAL (session 311, 311 % 5 == 1)
  - **Achievement**: Implemented Carousel Widget (v2.50.0) and executed full release

  **Completed Work**:
    - ✅ CI check: latest run queued (fix from session 310 in progress); 0 open sailor issues
    - ✅ Established v2.50.0 milestone: Carousel Widget
    - ✅ TDD Red: `test-writer` wrote 104 tests in `tests/carousel_test.zig`
    - ✅ TDD Green: `zig-developer` implemented `src/tui/widgets/carousel.zig`; exported from `tui.zig`; registered in `build.zig`
    - ✅ All 104 Carousel tests pass; overall suite exit code 0
    - ✅ Released v2.50.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr, zoltraak, silica
    - ✅ Discord notification sent

  **Carousel Widget Summary**:
    - `Carousel`: `items_count: usize`, `current: usize = 0`, `loop: bool = true`, `show_indicators: bool = true`, `show_arrows: bool = true`
    - Chars: `indicator_active_char: u21 = '●'`, `indicator_inactive_char: u21 = '○'`
    - Arrows: `left_arrow: []const u8 = "◄"`, `right_arrow: []const u8 = "►"`
    - Styles: `indicator_style`, `active_indicator_style`, `arrow_style`, `block: ?Block`
    - Methods: `init(count)`, `next()`, `prev()`, `goTo(usize)`, `isFirst/isLast()`, `count()`, `indicatorHeight()`, `contentArea(Rect) Rect`
    - Builder: withCurrent/Loop/ShowIndicators/ShowArrows/IndicatorActiveChar/IndicatorInactiveChar/LeftArrow/RightArrow/IndicatorStyle/ActiveIndicatorStyle/ArrowStyle/Block (all return value copies)
    - Navigation: loop=true wraps at ends; loop=false clamps; count=0 is always no-op
    - Render: block border → indicator row (◄ dots ►) at bottom of inner area → content area (caller renders)
    - Arrow visibility with loop=false: left hidden at first, right hidden at last
    - No allocations — items_count is just a usize

  **Current State**:
    - **Latest release**: v2.50.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Fix from session 310 queued (d207963), CI will complete soon

  **Next Priority**:
    - Establish v2.51.0 milestone (candidates: AnimatedBorder, CountdownTimer, ColorPicker enhanced, SplitLayout)

✅ **Session 310** — STABILIZATION MODE (2026-06-20)
  - **Mode**: STABILIZATION (session 310, 310 % 5 == 0)
  - **Achievement**: Fixed CI-RED: flawed pointer-inequality assertion in Select deinit test

  **Completed Work**:
    - ✅ CI status: RED on main (60/61 passed in select_test.zig)
    - ✅ Root cause: `select2.selected.ptr != selected_ptr` fails on Linux/glibc which reuses freed memory of same size
    - ✅ Fix: replaced pointer comparison with meaningful assertions (correct len + zero-init values)
    - ✅ All 6 cross-compile targets pass: Linux x86_64/ARM64, macOS x86_64/ARM64, Windows x86_64/ARM64
    - ✅ Full test suite passes locally: 7905 tests passed, 55 skipped
    - ✅ Committed + pushed: `fix: remove pointer-address assertion in Select deinit test`

  **Current State**:
    - **Latest release**: v2.49.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Fix pushed (d207963), CI will re-run

  **Next Priority**:
    - Establish v2.50.0 milestone (candidates: AnimatedBorder, Carousel, CountdownTimer, ColorPicker enhanced)

✅ **Session 309** — FEATURE MODE (2026-06-16)
  - **Mode**: NORMAL (session 309, 309 % 5 == 4)
  - **Achievement**: Implemented Wizard Widget (v2.49.0) and executed full release

  **Completed Work**:
    - ✅ CI check: queued (not RED); 0 open GitHub issues
    - ✅ Established v2.49.0 milestone: Wizard Widget
    - ✅ TDD Red: `test-writer` wrote 83 tests in `tests/wizard_test.zig`
    - ✅ TDD Green: `zig-developer` implemented `src/tui/widgets/wizard.zig`; exported from `tui.zig`; registered in `build.zig`
    - ✅ All 83 Wizard tests pass; overall suite exit code 0
    - ✅ Released v2.49.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#85, zoltraak#63, silica#74
    - ✅ Discord notification sent

  **Wizard Widget Summary**:
    - `Step`: nested struct `{ title: []const u8, description: []const u8 = "" }`
    - `Wizard`: `steps: []const Step`, `current: usize = 0`, `active_step_style/inactive_step_style/title_style/description_style/nav_style` (Style), `show_nav_hint: bool = true`, `block: ?Block = null`
    - Methods: `init(steps)`, `nextStep/prevStep()` (clamped), `goToStep(usize)` (bounds-checked), `isFirst/isLast()`, `stepCount()`, `currentStep() ?Step`
    - Geometry: `headerHeight()` → 3 if steps>0 else 0; `contentArea(Rect) Rect` → area minus block insets, header, nav hint row
    - Builder: withCurrent/ActiveStepStyle/InactiveStepStyle/TitleStyle/DescriptionStyle/NavStyle/ShowNavHint/Block (all return value copies)
    - Render: block border → step indicator row (●/○ + ─ connectors) → title row → separator → content area (caller renders) → nav hints "← Back" / "Next →"
    - No allocations — steps slice borrowed from caller

  **Current State**:
    - **Latest release**: v2.49.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Pushed commits, CI will run

  **Next Priority**:
    - Establish v2.50.0 milestone (candidates: AnimatedBorder, Carousel, CountdownTimer, ColorPicker enhanced)

✅ **Session 308** — FEATURE MODE (2026-06-16)
  - **Mode**: NORMAL (session 308, 308 % 5 == 3)
  - **Achievement**: Implemented Marquee Widget (v2.48.0) and executed full release

  **Completed Work**:
    - ✅ CI check: queued (not RED); 0 open GitHub issues
    - ✅ Established v2.48.0 milestone: Marquee Widget
    - ✅ TDD Red: `test-writer` wrote 100 tests in `tests/marquee_test.zig`
    - ✅ TDD Green: `zig-developer` implemented `src/tui/widgets/marquee.zig`; exported from `tui.zig`; registered in `build.zig`
    - ✅ All 100 Marquee tests pass; overall suite exit code 0
    - ✅ Released v2.48.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#84, zoltraak#62, silica#73
    - ✅ Discord notification sent

  **Marquee Widget Summary**:
    - `ScrollDirection` enum: `.left` (default), `.right` (nested public type in Marquee)
    - `Marquee`: `text: []const u8`, `offset: usize = 0`, `speed: u8 = 1`, `separator: []const u8 = " | "`, `direction: ScrollDirection = .left`, `style: Style = {}`, `block: ?Block = null`
    - Methods: `init(text)`, `textLen()` (text.len + sep.len, min 1), `currentOffset()` (offset % textLen), `tick()` (advance/retreat by speed, wraps), `reset()` (offset=0)
    - Builder: withText/Offset/Speed/Separator/Direction/Style/Block (all return value copies)
    - Render: single-row scrolling text, chars from repeating `text + separator` cycle, block border support
    - No allocations — borrowed slices

  **Current State**:
    - **Latest release**: v2.48.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Pushed commits, CI will run

  **Next Priority**:
    - Establish v2.49.0 milestone (candidates: WizardWidget, AnimatedBorder, Carousel, CountdownTimer)
✅ **Session 307** — FEATURE MODE (2026-06-16)
  - **Mode**: NORMAL (session 307, 307 % 5 == 2)
  - **Achievement**: Implemented DiffStat Widget (v2.47.0) and executed full release

  **Completed Work**:
    - ✅ CI check: queued (not RED); 0 open GitHub issues
    - ✅ Established v2.47.0 milestone: DiffStat Widget
    - ✅ TDD Red: `test-writer` wrote 77 tests in `tests/diffstat_test.zig`
    - ✅ TDD Green: `zig-developer` implemented `src/tui/widgets/diffstat.zig`; exported from `tui.zig`; registered in `build.zig`
    - ✅ All 77 DiffStat tests pass; overall suite exit code 0
    - ✅ Released v2.47.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#83, zoltraak#61, silica#72
    - ✅ Discord notification sent

  **DiffStat Widget Summary**:
    - `DiffStatEntry`: `filename: []const u8`, `insertions: u32`, `deletions: u32`, `binary: bool = false` (nested in DiffStat)
    - `DiffStat`: `entries: []const DiffStatEntry`, `max_filename_width: ?u16`, `bar_width: u16 = 20`, `insertion_char: u21 = '+'`, `deletion_char: u21 = '-'`
    - Styles: `insertion_style` (green), `deletion_style` (red), `filename_style`, `count_style`, `binary_style` (yellow), `block: ?Block`
    - Methods: `init(entries)`, `totalInsertions()`, `totalDeletions()`, `totalFiles()`, `computeMaxFilenameWidth()`, `computeMaxChanges()`, full builder API (10 with* methods), `render()`
    - Render format: `{filename:<width} | {bar} +{ins} -{del}` (binary shows "Bin" instead of bar)
    - Proportional bar: insertion_cols and deletion_cols scaled to bar_width by max_changes
    - No allocations — borrowed entries slice

  **Current State**:
    - **Latest release**: v2.47.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Pushed commits, CI will run

  **Next Priority**:
    - Establish v2.48.0 milestone (candidates: WizardWidget, KeyboardShortcutsHelp, AnimatedBorder, Marquee)

✅ **Session 304** — FEATURE MODE (2026-06-15)
  - **Mode**: NORMAL (session 304, 304 % 5 == 4)
  - **Achievement**: Implemented KeyValueViewer Widget (v2.45.0) and executed full release

  **Completed Work**:
    - ✅ CI check: queued (not RED); 0 open GitHub issues
    - ✅ Established v2.45.0 milestone: KeyValueViewer Widget
    - ✅ TDD Red: `test-writer` wrote 79 tests in `tests/keyvalue_viewer_test.zig`
    - ✅ TDD Green: `zig-developer` implemented `src/tui/widgets/keyvalue_viewer.zig`; exported from `tui.zig`; registered in `build.zig`
    - ✅ All 79 KeyValueViewer tests pass; overall suite exit code 0
    - ✅ Released v2.45.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#81, zoltraak#59, silica#70
    - ✅ Discord notification sent

  **KeyValueViewer Widget Summary**:
    - `KeyValueViewer`: `entries: []const Entry`, `selected: ?usize`, `offset: usize`, `key_width: KeyWidth = .auto`, `separator: []const u8 = ": "`, `block: ?Block`
    - `Entry`: nested struct `{ key: []const u8, value: []const u8 }`
    - `KeyWidth`: nested union `{ auto: void, fixed: u16 }`
    - Styles: `key_style`, `value_style`, `selected_key_style`, `selected_value_style`
    - Methods: `init(entries)`, `count()`, `computeKeyWidth()`, `selectedEntry()`, `selectNext/Prev()`, `scrollToSelected(visible_rows)`, full builder API (9 with* methods), `render()`
    - Render: key padded to key_col_width + separator + value truncated to remaining width
    - No allocations — borrowed entries slice

  **Current State**:
    - **Latest release**: v2.45.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Pushed commits, CI will run

  **Next Priority**:
    - Establish v2.46.0 milestone (candidates: Spinner, DiffStat, WizardWidget, KeyboardShortcutsHelp)

✅ **Session 303** — FEATURE MODE (2026-06-15)
  - **Mode**: NORMAL (session 303, 303 % 5 == 3)
  - **Achievement**: Implemented HexViewer Widget (v2.44.0) and executed full release

  **Completed Work**:
    - ✅ CI check: queued (not RED); 0 open GitHub issues
    - ✅ Established v2.44.0 milestone: HexViewer Widget
    - ✅ TDD Red: `test-writer` wrote 95 tests in `tests/hexviewer_test.zig`
    - ✅ TDD Green: `zig-developer` implemented `src/tui/widgets/hexviewer.zig`; exported from `tui.zig`; registered in `build.zig`
    - ✅ All 95 HexViewer tests pass; overall suite exit code 0
    - ✅ Released v2.44.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#80, zoltraak#58, silica#69
    - ✅ Discord notification sent

  **HexViewer Widget Summary**:
    - `HexViewer`: `data: []const u8`, `offset: usize` (aligned to bytes_per_row), `selected: ?usize`, `bytes_per_row: u8 = 16`, `group_size: u8 = 8`, `block: ?Block`
    - Styles: `address_style`, `hex_style`, `ascii_style`, `selected_style`
    - Toggles: `show_ascii: bool = true`, `show_address: bool = true`
    - Methods: `init(data)`, `selectNext/Prev()`, `selectNextRow/PrevRow()`, `pageDown/Up(rows)`, `scrollToSelected(visible_rows)`, `selectedByte() ?u8`, `byteCount() usize`, `totalRows() usize`, full builder API, `render()`
    - Format: `00000000  48 65 6c 6c 6f 2c 20 57  6f 72 6c 64 21 0a  |Hello, World!.|`
    - No allocations — borrowed data slice

  **Current State**:
    - **Latest release**: v2.44.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Pushed commits, CI will run

  **Next Priority**:
    - Establish v2.45.0 milestone (candidates: DiffStat, Spinner, WizardWidget, KeyValueViewer)

✅ **Session 302** — FEATURE MODE (2026-06-15)
  - **Mode**: NORMAL (session 302, 302 % 5 == 2)
  - **Achievement**: Implemented VirtualTable Widget (v2.43.0) and executed full release

  **Completed Work**:
    - ✅ CI check: queued (not RED); 0 open GitHub issues
    - ✅ Established v2.43.0 milestone: VirtualTable Widget
    - ✅ TDD Red: `test-writer` wrote 76 tests in `tests/virtualtable_test.zig`
    - ✅ TDD Green: `zig-developer` implemented `src/tui/widgets/virtualtable.zig` (355 lines); exported from `tui.zig`; registered in `build.zig`
    - ✅ All 76 VirtualTable tests pass; overall suite exit code 0
    - ✅ Released v2.43.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#79, zoltraak#57, silica#68
    - ✅ Discord notification sent

  **VirtualTable Widget Summary**:
    - `VirtualTable`: `columns: []const Column`, `rows: []const []const []const u8`, `selected: ?usize`, `offset: usize`, `block: ?Block`
    - Styles: `header_style`, `row_style`, `selected_style`, `column_spacing: u16`
    - Methods: `init(columns)`, `rowCount()`, `selectedRow()`, `selectNext/Prev()`, `pageDown/Up(size)`, `scrollToSelected(visible_rows)`, full builder API, `render()`
    - Key difference from Table: only renders visible rows (offset..offset+height), O(visible) not O(total)
    - Reuses Column/ColumnWidth/Alignment from table.zig
    - No allocations in any method

  **Current State**:
    - **Latest release**: v2.43.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Pushed commits, CI will run

  **Next Priority**:
    - Establish v2.44.0 milestone (candidates: HexViewer, WizardWidget, DiffStat, Spinner)

✅ **Session 301** — FEATURE MODE (2026-06-14)
  - **Mode**: NORMAL (session 301, 301 % 5 == 1)
  - **Achievement**: Implemented TreeTable Widget (v2.42.0) and executed full release

  **Completed Work**:
    - ✅ CI check: queued (not RED); 0 open GitHub issues
    - ✅ Established v2.42.0 milestone: TreeTable Widget
    - ✅ TDD Red: `test-writer` wrote 74 tests in `tests/treetable_test.zig`
    - ✅ TDD Green: `zig-developer` implemented `src/tui/widgets/treetable.zig` (453 lines); exported from `tui.zig`; registered in `build.zig`
    - ✅ All 74 TreeTable tests pass; overall suite exit code 0
    - ✅ Released v2.42.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr, zoltraak, silica
    - ✅ Discord notification sent

  **TreeTable Widget Summary**:
    - `TreeTableNode`: `cells: []const []const u8`, `children: []const TreeTableNode`, `expanded: bool = true`
    - `TreeTable`: `columns: []const Column`, `nodes: []const TreeTableNode`, `selected: ?usize`, `offset: usize`, `block: ?Block`
    - Styles: `header_style`, `row_style`, `selected_style`
    - Symbols: `expanded_symbol="▼ "`, `collapsed_symbol="▶ "`, `leaf_symbol="  "`, `indent: u16 = 2`
    - Methods: `init()`, `visibleCount()`, `selectNext/Prev()`, full builder API, `render()`
    - DFS pre-order traversal: collapsed nodes hide all descendants in count and render
    - Tree prefix: `(depth × indent spaces) + symbol + cells[0]`
    - Reuses `Column`, `ColumnWidth`, `Alignment` from table.zig

  **Current State**:
    - **Latest release**: v2.42.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Pushed commits, CI will run

  **Next Priority**:
    - Establish v2.43.0 milestone (candidates: VirtualTable, DiffStat, HexViewer, Spinner widget)

✅ **Session 300** — STABILIZATION MODE (2026-06-14)
  - **Mode**: STABILIZATION (session 300, 300 % 5 == 0)
  - **Achievement**: Test quality audit + cross-platform verification

  **Completed Work**:
    - ✅ CI check: queued (not RED); 0 open GitHub issues
    - ✅ All 6 cross-compile targets pass (Linux x86_64, Linux ARM64, macOS x86_64, macOS ARM64, Windows x86_64, Windows ARM64)
    - ✅ Full `zig build test` suite passes (exit code 0)
    - ✅ Code review of colorswatch_test.zig + rangeslider_test.zig revealed 2 critical + 7 warning quality issues
    - ✅ Fixed 8 weak assertions:
      - colorswatch: `char != ' ' or bg != null` → `char != ' '`
      - colorswatch: `selected < len or len==0` → `expectEqual(1, cs.selected)`
      - colorswatch: `selected <= 5` → `expectEqual(5, cs.selected)`
      - rangeslider: added missing immutability assertion in withHandleStyle test
      - rangeslider: `fg != null` → `expectEqual(?Color.cyan, fg)` for low focused handle
      - rangeslider: `fg != null` → `expectEqual(?Color.yellow, fg)` for high focused handle
      - rangeslider: added `!rowHasChar('2')` and `!rowHasChar('7')` for show_values=false
      - rangeslider: `low <= high` → `expectEqual(75,75)` for setRange(75,25) collapse
    - ✅ Committed + pushed: `test: strengthen weak assertions in colorswatch and rangeslider tests`

  **Current State**:
    - **Latest release**: v2.41.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Pushed test fixes, CI will run

  **Next Priority**:
    - Establish v2.42.0 milestone (candidates: VirtualTable, DiffStat, TreeTable, ColorPicker v2)

✅ **Session 299** — FEATURE MODE (2026-06-14)
  - **Mode**: NORMAL (session 299, 299 % 5 == 4)
  - **Achievement**: Implemented ColorSwatch Widget (v2.41.0) and executed full release

  **Completed Work**:
    - ✅ CI check: queued (not RED); 0 open GitHub issues
    - ✅ Established v2.41.0 milestone: ColorSwatch Widget
    - ✅ TDD Red: `test-writer` wrote 71 tests in `tests/colorswatch_test.zig`
    - ✅ TDD Green: `zig-developer` implemented `src/tui/widgets/colorswatch.zig` (350 lines); exported from `tui.zig`; registered in `build.zig`
    - ✅ All 71 ColorSwatch tests pass; overall suite exit code 0
    - ✅ Released v2.41.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#78, zoltraak#56, silica#67
    - ✅ Discord notification sent

  **ColorSwatch Widget Summary**:
    - `colors: []const Color`, `labels: []const []const u8`, `selected: usize`
    - `columns: u16 = 4`, `swatch_width: u16 = 3`, `swatch_height: u16 = 1`
    - `show_labels: bool`, `style/selected_style/label_style: Style`, `block: ?Block`
    - Navigation: `selectNext/Prev/Right/Left/Up/Down` (grid-aware, wrap/clamp)
    - `selectedColor() ?Color`
    - Builder: withColors/Labels/Selected/Columns/SwatchWidth/SwatchHeight/ShowLabels/Style/SelectedStyle/LabelStyle/Block
    - Render: fills cells with bg color, ● selection marker, optional labels, auto-scroll to keep selected visible

  **Current State**:
    - **Latest release**: v2.41.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Pushed commits, CI will run

  **Next Priority**:
    - Establish v2.42.0 milestone (candidates: VirtualTable, DiffStat, TreeTable, ColorPicker v2)

✅ **Session 298** — FEATURE MODE (2026-06-14)
  - **Mode**: NORMAL (session 298, 298 % 5 == 3)
  - **Achievement**: Implemented RangeSlider Widget (v2.40.0) and executed full release

  **Completed Work**:
    - ✅ CI check: queued (not RED); 0 open GitHub issues
    - ✅ Established v2.40.0 milestone: RangeSlider Widget
    - ✅ TDD Red: `test-writer` wrote 86 tests in `tests/rangeslider_test.zig`
    - ✅ TDD Green: `zig-developer` implemented `src/tui/widgets/rangeslider.zig` (363 lines); exported from `tui.zig`; registered in `build.zig`
    - ✅ All 86 RangeSlider tests pass; overall suite exit code 0
    - ✅ Released v2.40.0: bumped build.zig.zon, tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#77, zoltraak#55, silica#66
    - ✅ Discord notification sent

  **RangeSlider Widget Summary**:
    - `FocusedHandle` enum: .low, .high, .none
    - `low: f64`, `high: f64`, `min: f64`, `max: f64`, `step: f64`, `decimal_places: u8`
    - `focused_handle: FocusedHandle`, `label: []const u8`, `show_values: bool`
    - Track chars: `unselected_char: u21 = '─'`, `selected_char: u21 = '═'`
    - Handle chars: `low_handle_char: u21 = '◄'`, `high_handle_char: u21 = '►'`
    - Methods: `init()`, `moveLowLeft/Right()`, `moveHighLeft/Right()`, `setLow/High/Range()`, `isLowAtMin/isHighAtMax()`, `rangeSize()`, `lowRatio/highRatio()`
    - Builder: withMin/Max/Step/Low/High/DecimalPlaces/Label/ShowValues/Style/SelectedStyle/HandleStyle/FocusedStyle/LabelStyle/FocusedHandle/Block
    - Render: proportional handle positions, selected range fill, optional label, optional value overlays
    - Crossing prevention: moveLowRight capped at high, moveHighLeft floored at low

  **Current State**:
    - **Latest release**: v2.40.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **CI status**: Pushed commits, CI will run

  **Next Priority**:
    - Establish v2.41.0 milestone (candidates: ColorSwatch, VirtualTable, DiffStat, TreeTable)
