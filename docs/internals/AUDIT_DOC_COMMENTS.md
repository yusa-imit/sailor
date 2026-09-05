# Doc Comment Audit Report - sailor v1.27.0

**Milestone**: API Documentation Review
**Date**: 2026-03-29
**Scope**: All public functions (`pub fn`) in core modules, TUI framework, and key widgets

---

## Executive Summary

- **Total Functions Audited**: 1,471 public functions
- **Documented**: 1,136 (77%)
- **Undocumented**: 335 (23%)
- **Priority**: Focus on Core, TUI Core, and Key Widgets first

| Category | Documented | Total | % |
|----------|-----------|-------|---|
| **Core Modules** | 97 | 103 | 94% |
| **TUI Core** | 100 | 131 | 76% |
| **Key Widgets** | 74 | 87 | 85% |
| **Other Modules** | 865 | 1,150 | 75% |

---

## Core Modules (Priority 1)

Overall: **97/103 documented (94%)**

### term.zig
- **Status**: ✗ Needs documentation
- **Documented**: 23/28 (82%)
- **Missing doc comments**:
  1. Line 693: `init()` — MockTerminal initialization
  2. Line 703: `setResponse()` — Configure mock response
  3. Line 709: `setNoResponse()` — Disable mock response
  4. Line 713: `setChunkedResponse()` — Set chunked response mode
  5. Line 720: `fd()` — Get file descriptor

**Context**: MockTerminal test utilities. These are internal test helpers, not primary API.

### color.zig
- **Status**: ✓ Fully documented
- **Documented**: 18/18 (100%)

### arg.zig
- **Status**: ✓ Fully documented
- **Documented**: 14/14 (100%)

### repl.zig
- **Status**: ✓ Fully documented
- **Documented**: 3/3 (100%)

### progress.zig
- **Status**: ✗ Needs documentation
- **Documented**: 16/17 (94%)
- **Missing doc comments**:
  1. Line 27: `frames()` — Returns spinner animation frames

**Context**: Single high-impact function. Quick fix.

### fmt.zig
- **Status**: ✓ Fully documented
- **Documented**: 23/23 (100%)

---

## TUI Core Modules (Priority 2)

Overall: **100/131 documented (76%)**

### tui/tui.zig
- **Status**: ✓ Fully documented
- **Documented**: 8/8 (100%)

### tui/style.zig
- **Status**: ✓ Fully documented
- **Documented**: 30/30 (100%)

### tui/buffer.zig
- **Status**: ✓ Fully documented
- **Documented**: 21/21 (100%)

### tui/layout.zig
- **Status**: ✓ Fully documented
- **Documented**: 8/8 (100%)

### tui/symbols.zig
- **Status**: ✓ Fully documented
- **Documented**: 8/8 (100%)

### tui/widget_trait.zig
- **Status**: ✗ Needs documentation
- **Documented**: 13/33 (39%)
- **Missing doc comments** (20 functions):
  - `init()` — Multiple trait implementations (lines 102, 168, 371)
  - `deinit()` — Resource cleanup (line 110)
  - `measure()` — Size calculation (multiple implementations)
  - `render()` — Drawing to buffer (multiple implementations)

**Context**: Core widget trait definitions. Many are template implementations within trait blocks. High priority due to framework importance.

### tui/widget_helpers.zig
- **Status**: ✗ Needs documentation
- **Documented**: 12/23 (52%)
- **Missing doc comments** (11 functions):
  - `init()` — Helper struct initialization (lines 95, 168, 371)
  - `render()` — Rendering helpers (lines 99, 184, 411, 452)
  - `measure()` — Size measurement (lines 176, 465)
  - `deinit()` — Cleanup (line 263)

**Context**: Internal widget helper utilities. Important for widget implementation consistency.

---

## Key Widgets (Priority 3)

Overall: **74/87 documented (85%)**

### tui/widgets/block.zig
- **Status**: ✓ Fully documented
- **Documented**: 11/11 (100%)

### tui/widgets/paragraph.zig
- **Status**: ✓ Fully documented
- **Documented**: 8/8 (100%)

### tui/widgets/input.zig
- **Status**: ✓ Fully documented
- **Documented**: 8/8 (100%)

### tui/widgets/list.zig
- **Status**: ✓ Fully documented
- **Documented**: 8/8 (100%)

### tui/widgets/table.zig
- **Status**: ✓ Fully documented
- **Documented**: 13/13 (100%)

### tui/widgets/tree.zig
- **Status**: ✓ Fully documented
- **Documented**: 16/16 (100%)

### tui/widgets/form.zig
- **Status**: ✗ Needs documentation
- **Documented**: 10/23 (43%)
- **Missing doc comments** (13 functions):
  - **Field struct**:
    1. Line 29: `init()` — Create field
    2. Line 44: `withValidator()` — Add validator
    3. Line 50: `withPassword()` — Mark as password field
    4. Line 56: `withMaxLength()` — Set max length
    5. Line 62: `validate()` — Validate field value
  - **Form struct**:
    6. Line 98: `init()` — Initialize form
    7. Line 109: `withBlock()` — Add border block
    8. Line 115: `withStyle()` — Set normal style
    9. Line 121: `withFocusedStyle()` — Set focused style
    10. Line 127: `withErrorStyle()` — Set error style
    11. Line 133: `withLabelWidth()` — Set label column width
    12. Line 139: `withHelp()` — Toggle help visibility
    13. Line 252: `render()` — Render form to buffer

**Context**: Public form widget API. Important for user-facing documentation.

---

## Other Modules (Priority 4)

Overall: **865/1,150 documented (75%)**

### High-Impact Undocumented (6-10+ functions)

#### tui/gamepad.zig
- **Status**: ✗ Critical
- **Documented**: 3/29 (10%)
- **Missing**: 26 functions
- **Impact**: Entire gamepad input abstraction layer undocumented

#### tui/widgets/multicursor.zig
- **Status**: ✗ Critical
- **Documented**: 4/32 (12%)
- **Missing**: 28 functions
- **Impact**: Multi-cursor editing system largely undocumented

#### tui/widgets/editor.zig
- **Status**: ✗ Critical
- **Documented**: 0/20 (0%)
- **Missing**: 20 functions
- **Impact**: Text editor widget completely undocumented

#### tui/widgets/richtext.zig
- **Status**: ✗ High
- **Documented**: 28/58 (48%)
- **Missing**: 30 functions
- **Impact**: Rich text widget with significant missing docs

#### tui/timer.zig
- **Status**: ✗ High
- **Documented**: 5/24 (21%)
- **Missing**: 19 functions
- **Impact**: Timer abstraction largely undocumented

#### tui/widgets/autocomplete.zig
- **Status**: ✗ High
- **Documented**: 2/16 (12%)
- **Missing**: 14 functions
- **Impact**: Autocomplete widget largely undocumented

### Moderate Gaps (5-10 functions)

- **tui/profiler.zig**: 11/18 (61%) — 7 missing
- **tui/termcap.zig**: 4/16 (25%) — 12 missing
- **tui/audit.zig**: 15/20 (75%) — 5 missing
- **tui/blur.zig**: 3/7 (43%) — 4 missing
- **tui/budget.zig**: 6/9 (67%) — 3 missing
- **tui/datasource.zig**: 18/24 (75%) — 6 missing
- **tui/inspector.zig**: 30/36 (83%) — 6 missing
- **tui/keyboard_nav.zig**: 10/14 (71%) — 4 missing
- **tui/kitty.zig**: 7/9 (78%) — 2 missing
- **tui/layout_cache.zig**: 5/7 (71%) — 2 missing
- **tui/line_break.zig**: 1/2 (50%) — 1 missing
- **tui/mouse_trait.zig**: 6/11 (55%) — 5 missing
- **tui/overlay.zig**: 11/13 (85%) — 2 missing
- **tui/richtext_parser.zig**: 2/4 (50%) — 2 missing
- **tui/screen_reader.zig**: 12/13 (92%) — 1 missing
- **tui/session.zig**: 11/15 (73%) — 4 missing
- **tui/sixel.zig**: 2/4 (50%) — 2 missing
- **tui/syntax.zig**: 2/9 (22%) — 7 missing
- **tui/touch.zig**: 5/9 (56%) — 4 missing
- **tui/validators.zig**: 17/18 (94%) — 1 missing
- **tui/widgets/canvas.zig**: 10/11 (91%) — 1 missing
- **tui/widgets/checkbox.zig**: 7/20 (35%) — 13 missing
- **tui/widgets/completion_popup.zig**: 7/8 (88%) — 1 missing
- **tui/widgets/debugger.zig**: 5/10 (50%) — 5 missing
- **tui/widgets/dialog.zig**: 4/5 (80%) — 1 missing
- **tui/widgets/input_map.zig**: 12/14 (86%) — 2 missing
- **tui/widgets/notification.zig**: 6/9 (67%) — 3 missing
- **tui/widgets/particles.zig**: 6/12 (50%) — 6 missing
- **tui/widgets/popup.zig**: 3/4 (75%) — 1 missing
- **tui/widgets/profiler.zig**: 9/11 (82%) — 2 missing
- **tui/widgets/radio.zig**: 8/16 (50%) — 8 missing
- **tui/widgets/select.zig**: 6/15 (40%) — 9 missing
- **tui/widgets/terminal.zig**: 9/15 (60%) — 6 missing
- **tui/widgets/theme_editor.zig**: 10/11 (91%) — 1 missing

### Fully Documented (Good Examples)

- accessibility.zig: 5/7 (71%)
- bidi.zig: 3/3 (100%)
- command.zig: 18/18 (100%)
- docgen.zig: 7/7 (100%)
- env.zig: 3/3 (100%)
- pool.zig: 6/6 (100%)
- tui/animation.zig: 35/35 (100%)
- tui/async_loop.zig: 12/12 (100%)
- tui/batch.zig: 8/8 (100%)
- tui/buffer_compression.zig: 4/4 (100%)
- tui/composition.zig: 7/7 (100%)
- tui/effects.zig: 5/5 (100%)
- tui/flexbox.zig: 6/6 (100%)
- tui/grid.zig: 2/2 (100%)
- tui/hotreload.zig: 5/5 (100%)
- tui/incremental_layout.zig: 3/3 (100%)
- tui/lazy.zig: 16/16 (100%)
- tui/mouse.zig: 5/5 (100%)
- tui/responsive.zig: 10/10 (100%)
- tui/text_measure.zig: 2/2 (100%)
- tui/theme.zig: 11/11 (100%)
- tui/theme_loader.zig: 2/2 (100%)
- tui/transition.zig: 25/25 (100%)
- tui/transitions.zig: 16/16 (100%)
- tui/viewport.zig: 9/9 (100%)
- tui/virtual.zig: 3/3 (100%)
- tui/widgets/barchart.zig: 9/9 (100%)
- tui/widgets/calendar.zig: 29/29 (100%)
- tui/widgets/chunkedbuffer.zig: 7/7 (100%)
- tui/widgets/debug.zig: 8/8 (100%)
- tui/widgets/filebrowser.zig: 25/25 (100%)
- tui/widgets/gauge.zig: 11/11 (100%)
- tui/widgets/heatmap.zig: 1/1 (100%)
- tui/widgets/histogram.zig: 10/10 (100%)
- tui/widgets/httpclient.zig: 6/6 (100%)
- tui/widgets/linechart.zig: 12/12 (100%)
- tui/widgets/logviewer.zig: 16/16 (100%)
- tui/widgets/markdown.zig: 12/12 (100%)
- tui/widgets/menu.zig: 15/15 (100%)
- tui/widgets/piechart.zig: 5/5 (100%)
- tui/widgets/scatterplot.zig: 13/13 (100%)
- tui/widgets/scrollview.zig: 8/8 (100%)
- tui/widgets/sparkline.zig: 6/6 (100%)
- tui/widgets/statusbar.zig: 6/6 (100%)
- tui/widgets/streaming_table.zig: 10/10 (100%)
- tui/widgets/tabs.zig: 7/7 (100%)
- tui/widgets/taskrunner.zig: 12/12 (100%)
- tui/widgets/textarea.zig: 10/10 (100%)
- tui/widgets/timeseries.zig: 12/12 (100%)
- tui/widgets/virtuallist.zig: 9/9 (100%)
- tui/widgets/websocket.zig: 12/12 (100%)
- unicode.zig: 3/3 (100%)

---

## Recommendations by Phase

### Phase 1: Critical (Quick Wins)
**Estimated effort**: 2-4 hours

1. **progress.zig** (1 function)
   - `frames()` — 1 line doc comment

2. **term.zig** (5 functions)
   - MockTerminal test helpers (test-scoped, lower priority but simple)

3. **tui/widgets/form.zig** (13 functions)
   - Public widget builder API — important for users
   - Mostly builder pattern methods with predictable docs

### Phase 2: High Impact (2-4 hours)

1. **tui/widget_trait.zig** (20 functions)
   - Core framework abstraction
   - Many template methods that can use similar doc patterns

2. **tui/widget_helpers.zig** (11 functions)
   - Supporting infrastructure for widgets

### Phase 3: Widget Completeness (4-8 hours)

1. **tui/widgets/editor.zig** (20 functions, 0% documented)
2. **tui/widgets/multicursor.zig** (28 functions, 12% documented)
3. **tui/widgets/richtext.zig** (30 functions, 48% documented)
4. **tui/widgets/autocomplete.zig** (14 functions, 12% documented)
5. **tui/widgets/checkbox.zig** (13 functions, 35% documented)
6. **tui/widgets/radio.zig** (8 functions, 50% documented)
7. **tui/widgets/select.zig** (9 functions, 40% documented)

### Phase 4: Infrastructure & Utilities (4-6 hours)

1. **tui/gamepad.zig** (26 functions, 10% documented)
2. **tui/timer.zig** (19 functions, 21% documented)
3. **tui/termcap.zig** (12 functions, 25% documented)
4. **tui/syntax.zig** (7 functions, 22% documented)

---

## Doc Comment Pattern Guidelines

To maintain consistency, follow these patterns:

### 1. Function Initialization
```zig
/// Initializes a [Type] with default values.
/// The returned instance must be freed with `.deinit()`.
pub fn init(allocator: std.mem.Allocator) [Type] {
```

### 2. Builder Methods
```zig
/// Sets the [property] to the given value.
/// Returns `self` for method chaining.
pub fn withProperty(self: [Type], value: T) [Type] {
```

### 3. Lifecycle Methods
```zig
/// Frees resources associated with this instance.
pub fn deinit(self: *[Type]) void {
```

### 4. Query/Getter Methods
```zig
/// Returns the current [property].
pub fn property(self: [Type]) T {
```

### 5. Rendering/Display Methods
```zig
/// Renders this widget to the given buffer within the specified area.
pub fn render(self: [Type], buf: *Buffer, area: Rect) !void {
```

### 6. Measurement Methods
```zig
/// Calculates the minimum size needed to display this widget.
pub fn measure(self: [Type], allocator: std.mem.Allocator, max_width: u16, max_height: u16) !Size {
```

---

## Files Ready for Documentation Review

The following files have existing doc comments and serve as good reference models:

- `/Users/fn/codespace/sailor/src/color.zig` (100%)
- `/Users/fn/codespace/sailor/src/arg.zig` (100%)
- `/Users/fn/codespace/sailor/src/fmt.zig` (100%)
- `/Users/fn/codespace/sailor/src/tui/style.zig` (100%)
- `/Users/fn/codespace/sailor/src/tui/buffer.zig` (100%)
- `/Users/fn/codespace/sailor/src/tui/widgets/block.zig` (100%)

---

## Next Steps

1. **Create feature branch**: `feat/add-doc-comments-v1.27`
2. **Phase 1**: Document core modules (6 functions)
3. **Phase 2**: Document TUI framework traits and helpers (31 functions)
4. **Phase 3**: Complete key widgets (13 functions)
5. **Phase 4+**: Address high-impact modules as bandwidth allows
6. **Validation**: Run doc generation and verify no broken references
7. **Release**: Include doc improvements in v1.27.0 release notes

---

## Notes

- Test utility functions in `term.zig` (MockTerminal) are lower priority unless they're part of public testing API
- Widget trait implementations follow template patterns that can be grouped for consistent documentation
- Builder pattern methods in form widgets follow a consistent interface that can use template documentation
- Some advanced modules (gamepad, timer, syntax) may benefit from architectural documentation in addition to function-level docs
