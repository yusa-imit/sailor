# sailor — Milestones

## Current Status

- **Latest release**: v2.32.0 (2026-06-11) — CommandBar Widget
- **Latest minor**: v2.32.0 (2026-06-11) — CommandBar Widget
- **Next release**: v2.33.0 — Inspector Widget
- **Active milestones**: 2 pending implementation
- **Blockers**: None

### v2.34.0 — StatusGrid Widget (Target: 2026-08-21)

**Theme**: Multi-cell status grid for monitoring dashboards — N×M cells each with label, value, and status color. Useful for cluster health, pipeline overview, and metric panels.

**Checklist**:
- [ ] **src/tui/widgets/status_grid.zig** — StatusGrid: init with cells slice (rows×cols), StatusCell (label, value, status); StatusLevel enum (ok/warn/error_/unknown) with color(); cursor navigation (moveUp/Down/Left/Right, clamped); selectedCell(); withRows/withCols/withBlock/withCellStyle/withOkStyle/withWarnStyle/withErrorStyle/withUnknownStyle/withShowValues builder API; render draws labeled cells with status background color
- [ ] **tests/status_grid_test.zig** — StatusGrid tests (init, navigation, selectedCell, status colors, render to Buffer, edge cases: empty cells, zero area, 1×1 grid, narrow area) — 55+ tests
- [ ] Export StatusGrid, StatusCell, StatusLevel via tui.zig widgets struct
- [ ] Add status_grid_tests to build.zig
- [ ] Release v2.34.0

**Success Criteria**:
- moveRight/Left/Up/Down clamp cursor within [0, cols-1] × [0, rows-1]
- selectedCell() returns pointer to current StatusCell
- StatusLevel.color() returns appropriate Color (.green/.yellow/.red/.bright_black)
- render draws each cell as a bordered box with label+value+status indicator
- Zero-area, empty cells, 1×1 edge cases handled without crash

**Notes**:
- No allocator — cells slice borrowed from caller
- Useful for: zr (pipeline status overview), zoltraak (cluster health), silica (table status panel)

### v2.33.0 — Inspector Widget (Target: 2026-08-14)

**Theme**: Collapsible key-value property inspector for examining structured data — fields, types, values, optional filtering. Useful for Redis key inspection, schema details, task properties.

**Checklist**:
- [ ] **src/tui/widgets/inspector.zig** — Inspector: init with fields slice; InspectorField (key, value, field_type, depth); scrollUp/scrollDown/goToTop/goToBottom navigation; filterBy(query) hides non-matching fields; clearFilter(); withBlock/withKeyStyle/withValueStyle/withTypeStyle/withFilterStyle/withShowTypes/withShowFilter builder API; render draws key: value [type] rows with indentation for depth
- [ ] **tests/inspector_test.zig** — Inspector tests (init, navigation, filter, clearFilter, render to Buffer, edge cases: empty fields, zero area, single field, deep nesting, narrow area) — 55+ tests
- [ ] Export Inspector, InspectorField via tui.zig widgets struct
- [ ] Add inspector_tests to build.zig
- [ ] Release v2.33.0

**Success Criteria**:
- scrollDown/scrollUp clamp to [0, visible_fields.len - 1]
- filterBy("query") case-insensitive match on field key
- render indents rows by depth (2 spaces per level)
- withShowTypes(true) renders [type] tag after value
- Zero-area, empty fields, deep nesting handled without crash

**Notes**:
- No allocator — fields slice borrowed from caller
- Useful for: zoltraak (Redis key inspector), silica (schema inspector), zr (task detail viewer)

### v2.32.0 — CommandBar Widget (Target: 2026-08-07)

**Theme**: Command palette / omnibox with command registration, fuzzy search, keyboard shortcut display, and ranked results list. Used for command dispatch in TUI applications.

**Checklist**:
- [x] **src/tui/widgets/command_bar.zig** — CommandBar: init(allocator) stores registered commands; Command struct (name, description, shortcut); register(cmd)/unregister(name); setQuery(text)/clearQuery(); results() returns ranked matches (prefix-match first, then substring); moveCursorDown/moveCursorUp/selectedCommand(); withBlock/withQueryStyle/withResultStyle/withSelectedStyle/withShortcutStyle/withPlaceholder builder API; render draws query input + results list
- [x] **tests/command_bar_test.zig** — CommandBar tests (init, register, unregister, setQuery ranking, clearQuery, moveCursor, selectedCommand, render to Buffer, edge cases: no commands, no match, empty query, zero area) — 63 tests
- [x] Export CommandBar, Command via tui.zig widgets struct
- [x] Add command_bar_tests to build.zig
- [x] Release v2.32.0

**Success Criteria**:
- register() adds command; unregister(name) removes it (no-op if not found)
- setQuery("") returns all registered commands in registration order
- setQuery("q") returns prefix matches first, then substring matches, no duplicates
- moveCursorDown/Up cycle within results slice bounds
- selectedCommand() returns the Command at cursor (null if no results)
- render draws query line at top, results below with shortcut right-aligned
- Zero-area, no-match, empty-commands edge cases handled without crash

**Notes**:
- CommandBar needs allocator for dynamic results slice (unlike most widgets)
- Useful for: silica (SQL commands), zoltraak (CLI command palette), zr (task shortcuts)

### v2.31.0 — Timeline Widget (Target: 2026-07-31)

**Theme**: Vertical/horizontal timeline display for event history with timestamps, status markers, and scrollable navigation

**Checklist**:
- [x] **src/tui/widgets/timeline.zig** — Timeline: init with events slice, scrollUp/scrollDown/goToTop/goToBottom navigation; TimelineEvent (timestamp, title, description, status); TimelineStatus enum (pending/active/completed/failed/skipped); withDirection/withBlock/withStyle/withActiveStyle/withCompletedStyle/withFailedStyle/withShowTimestamps/withConnectorChar builder API; render draws connector line with event markers
- [x] **tests/timeline_test.zig** — Timeline tests (init, navigation, status rendering, direction modes, timestamps, render to Buffer, edge cases: empty events, zero area, single event, narrow area) — 58 tests
- [x] Export Timeline, TimelineEvent, TimelineStatus, TimelineDirection via tui.zig widgets struct
- [x] Add timeline_tests to build.zig
- [x] Release v2.31.0

**Success Criteria**:
- scrollDown/scrollUp clamp scroll_offset to [0, events.len - viewport]
- goToTop/goToBottom set scroll_offset to extremes
- render draws a vertical connector line with ○/●/✓/✗/⊘ markers per status
- Active event highlighted with active_style; completed with completed_style; failed with failed_style
- Timestamps rendered left-aligned before the connector when withShowTimestamps(true)
- horizontal direction renders events left-to-right with connector between them
- Zero-area, empty events, single event handled without crash

**Notes**:
- No allocator in Timeline — events slice borrowed from caller
- TimelineStatus mirrors Pipeline/Stepper status conventions for consistency
- Useful for: zr (task history), zoltraak (operation log), silica (migration history)

### v2.30.0 — Accordion Widget (Target: 2026-07-24)

**Theme**: Collapsible/expandable section groups with header/content structure, single or multi-expand mode, and keyboard navigation

**Checklist**:
- [x] **src/tui/widgets/accordion.zig** — Accordion: init with sections slice, toggleCurrent/expandCurrent/collapseCurrent/expandAll/collapseAll, moveCursorUp/moveCursorDown navigation; AccordionSection (title, content_lines, expanded); single_expand mode (only one open at a time); withBlock/withHeaderStyle/withExpandedStyle/withCursorStyle/withExpandIcon/withCollapseIcon/withSingleExpand builder API; render draws header rows + content rows
- [x] **tests/accordion_test.zig** — Accordion tests (init, toggle, expand/collapse, moveCursorUp/Down, single_expand mode, expandAll/collapseAll, isExpanded, render to Buffer, edge cases: empty sections, zero area, all collapsed, all expanded, narrow) — 74 tests
- [x] Export Accordion, AccordionSection via tui.zig widgets struct
- [x] Add accordion_tests to build.zig
- [x] Release v2.30.0

**Success Criteria**:
- toggleCurrent flips expanded state of cursor section
- single_expand mode collapses all others when one is expanded
- expandAll/collapseAll affect all sections regardless of mode
- moveCursorDown/Up wrap at boundaries
- render draws header rows always; content rows only when expanded
- withExpandIcon/withCollapseIcon customize the ▶/▼ indicators
- Zero-area, empty sections, all-collapsed/all-expanded cases handled without crash

**Notes**:
- No allocator in Accordion — sections slice borrowed from caller
- AccordionSection has expanded field mutated in-place (caller owns the slice)
- Useful for: zoltraak (config sections), silica (schema groups), zr (help topics)

### v2.29.0 — Toast Manager (Target: 2026-07-17)

**Theme**: Queue-based notification manager rendering stacked toast messages with auto-dismiss, severity levels, and configurable screen positioning

**Checklist**:
- [x] **src/tui/widgets/toast_manager.zig** — ToastManager: fixed-capacity queue (MAX_TOASTS=8), push/dismiss(index)/dismissAll, tick (decrement auto-dismiss counters, evict expired); ToastItem (message, level, title, ticks_remaining: 0=persistent); withPosition/withMaxVisible/withWidth/withSpacing/withInfoStyle/withSuccessStyle/withWarningStyle/withErrorStyle builder API; render draws stacked visible toasts in corner
- [x] **tests/toast_manager_test.zig** — ToastManager tests (init, push, dismiss, dismissAll, tick auto-evict, tick persistent, render stacked, position calculations, style per level, edge cases: empty queue, full queue eviction, zero area, narrow area, max_visible limit) — 50 tests
- [x] Export ToastManager, ToastItem, ToastLevel, ToastPosition via tui.zig widgets struct
- [x] Add toast_manager_tests to build.zig
- [x] Release v2.29.0

**Success Criteria**:
- push() adds to queue; when queue is full (8), evicts oldest before adding
- tick() decrements ticks_remaining on non-zero entries; removes entries at 0
- dismiss(index) removes entry at index, shifts remaining entries left
- dismissAll() clears all entries
- render draws up to max_visible toasts stacked from the position corner
- Each toast rendered with level icon, optional title line, message text, border
- toastCount() returns current number of queued toasts
- Zero-area, empty queue, full queue, max_visible=1 cases handled without crash

**Notes**:
- No allocator in ToastManager — fixed array, no heap
- Level and Position types defined locally (ToastLevel, ToastPosition) to avoid import ambiguity
- auto-dismiss: caller calls tick() each frame; ticks_remaining=0 means persistent
- Consumer use: silica (query result notifications), zoltraak (operation feedback), zr (task completion)

### v2.28.0 — Context Menu Widget (Target: 2026-07-17)

**Theme**: Positional popup context menu with Action/Separator/Submenu item types, keyboard navigation, screen-boundary-aware positioning, and styled rendering

**Checklist**:
- [x] **src/tui/widgets/context_menu.zig** — ContextMenu: init with items slice, moveDown/moveUp navigation (skip separators+disabled, wrap-around), actionCount, currentItem, isCurrentSelectable, fittingArea(screen) for auto-positioning, withOrigin/withBlock/withItemStyle/withSelectedStyle/withDisabledStyle/withShortcutStyle/withCursor builder API; render draws bordered item list with selected_style/disabled_style/shortcut right-alignment/submenu indicator
- [x] **tests/context_menu_test.zig** — ContextMenu tests (init, builder, actionCount, moveDown/moveUp navigation & wrapping, currentItem, isCurrentSelectable, fittingArea bounds, render styles, edge cases: empty/single/all-separators/zero-area/narrow) — 79 tests
- [x] Export ContextMenu via tui.zig widgets struct
- [x] Add context_menu_tests to build.zig
- [x] Release v2.28.0

**Success Criteria**:
- moveDown/moveUp skip separators and disabled actions, wrap at list boundaries
- actionCount counts action+submenu items (not separators)
- fittingArea auto-positions to avoid screen overflow
- render applies selected_style to cursor row, disabled_style to disabled rows, separators as '─' horizontal rules, shortcuts right-aligned, submenu indicator '>'
- Empty list, single item, all-separators edge cases handled without crash

**Notes**:
- No allocator in ContextMenu — all slices borrowed from caller
- Distinct from menu.zig (menu bar at fixed position); context menu triggers at a dynamic (origin_x, origin_y) point
- Consumer use: right-click menus in silica SQL shell, action menus in zoltraak, context operations in zr

### v2.27.0 — Color Picker Widget (Target: 2026-07-10)

**Theme**: Interactive color selection widget supporting 256-color palette, basic 16-color palette, and RGB slider modes

**Checklist**:
- [x] **src/tui/widgets/color_picker.zig** — ColorPicker: init with ColorPickerMode (palette_256/palette_16/rgb_sliders), cursor navigation (moveUp/Down/Left/Right for palette, incrementComponent/decrementComponent for RGB), selectedColor() returns Color, setColor(Color) initializes state, withBlock/withStyle/withCursorStyle/withMode/withColor builder API; render draws color swatches in palette mode or labeled slider bars in RGB mode
- [x] **tests/color_picker_test.zig** — ColorPicker tests (init, mode switching, palette navigation, RGB slider navigation, selectedColor, setColor, render to Buffer, edge cases: zero area, narrow area, each mode) — 89 tests
- [x] Export ColorPicker, ColorPickerMode, RgbComponent via tui.zig widgets struct
- [x] Add color_picker_tests to build.zig
- [x] Release v2.27.0

**Success Criteria**:
- moveUp/Down/Left/Right navigate cursor on the 16x16 palette grid (palette_256) or 4x4 grid (palette_16), clamped to bounds
- incrementComponent/decrementComponent adjust R/G/B value (0-255) in rgb_sliders mode, clamped to [0, 255]
- nextComponent/prevComponent cycle through R/G/B sliders
- selectedColor() returns the Color at current cursor position (palette modes) or Color.rgb(r, g, b) (RGB mode)
- setColor(Color.index(n)) positions cursor at that palette cell; setColor(Color.rgb(r,g,b)) sets RGB sliders
- render fills each cell with the color's background for visual preview (palette modes)
- render draws three labeled bars `R: ███░░ 128` in RGB mode
- Zero-area and narrow-area cases handled without crash

**Notes**:
- No allocator in ColorPicker — all state fits in the struct
- palette_256: cursor_x in [0,15], cursor_y in [0,15] → color index = cursor_y*16 + cursor_x
- palette_16: cursor_x in [0,7], cursor_y in [0,1] → color index = cursor_y*8 + cursor_x (maps to ANSI 0-15)
- rgb_sliders: component enum (r/g/b), value [0,255]; selectedColor = Color.rgb(r, g, b)
- Consumer use: silica (column color picker), zoltraak (key highlight color), zr (label color)

### v2.26.0 — Pager Widget (Scrollable Text Viewer) (Target: 2026-07-26)

**Theme**: Scrollable text pager with search highlighting, line numbers, and vim-style navigation

**Checklist**:
- [x] **src/tui/widgets/pager.zig** — Pager: init with lines slice, scrollUp/Down/Left/Right/pageUp/Down/goToTop/goToBottom/goToLine navigation, search with highlight, withLineNumbers/withWrap/withStyle/withHighlightStyle/withBlock/withSearchQuery builder API; render with optional line numbers, horizontal scroll, search highlight
- [x] **tests/pager_test.zig** — Pager tests (init, scroll navigation, goToLine, goToTop/goToBottom, pageUp/pageDown, search, render, line numbers, wrap, edge cases: empty lines, zero area, single line) — 61 tests
- [x] Export Pager via tui.zig widgets struct
- [x] Add pager_tests to build.zig
- [x] Release v2.26.0

**Success Criteria**:
- scrollDown/Up clamp to valid range; scrollRight/Left clamp to 0 and max line width
- pageDown moves scroll_y by area height; pageUp moves it back
- goToLine(n) clamps to [0, lines.len - 1]; goToTop/goToBottom go to extremes
- search(query) stores the query; render highlights all matching substrings
- Line numbers render as right-aligned with separator when enabled
- Wrap mode renders long lines across multiple display rows
- Zero-area and empty-lines cases handled without crash

**Notes**:
- No allocator stored in Pager — all slices are borrowed from caller
- search_query is a simple substring match (case-sensitive by default)
- withCaseSensitive(bool) builder for case sensitivity toggle
- Pager is purely presentational — navigation methods return new Pager (builder pattern) or mutate self (nav pattern)
- Consumer use: silica SQL output pager, zoltraak value viewer, zr help output

### v2.25.0 — Select/Dropdown Widget (Target: 2026-07-19)

**Theme**: Single-select (radio) and multi-select (checkbox) dropdown widget with scrolling support

**Checklist**:
- [x] **src/tui/widgets/select.zig** — Select: init/deinit, next/prev navigation with wrap, selectCurrent (single mode), toggleCurrent (multi mode), currentItem, selectedItems, adjustScroll, withBlock/withStyle/withHighlightStyle/withSelectedStyle/withMaxVisible/withHelp builder API; render with radio/checkbox indicators, scroll arrows, help text, UTF-8 safe text rendering
- [x] **tests/select_test.zig** — Select tests (init, navigation, single-select, multi-select, scrolling, rendering, builder pattern, edge cases) — 56 tests
- [x] Export Select via tui.zig (already present at tui.zig:166)
- [x] Add select_tests to build.zig
- [x] Release v2.25.0

**Success Criteria**:
- next/prev wrap correctly; adjustScroll keeps current item in view
- selectCurrent clears all others (single mode); toggleCurrent flips one (multi mode)
- selectedItems returns slice of selected item strings
- render draws ○/● for single mode, [ ]/[✓] for multi mode
- Scroll arrows appear when scrolled past top or bottom
- All edge cases (empty items, zero area, out-of-bounds current) handled without panic

**Notes**:
- adjustScroll is pub to allow external callers to pre-position the scroll
- UTF-8 aware rendering: codepoints decoded properly for arrow chars (↑/↓)
- highlight_style defaults to underline (not reversed) for better terminal compatibility

### v2.24.0 — Multi-Select & Reorderable List Widgets (Target: 2026-07-12)

**Theme**: Interactive list widgets with multi-selection and keyboard drag-and-drop reordering

**Checklist**:
- [x] **src/tui/widgets/multi_select_list.zig** — MultiSelectList: cursor navigation (moveCursorUp/Down), toggleCursor, selectAll/deselectAll, countSelected, isSelected, render with cursor/selected/unselected symbols and styles; optional Block wrapper
- [x] **tests/multi_select_list_test.zig** — MultiSelectList tests (initialization, navigation, toggle, selectAll/deselectAll, countSelected, isSelected bounds, render symbols, empty/single-item edge cases) — 40+ tests
- [x] **src/tui/widgets/reorderable_list.zig** — ReorderableList: order index array, moveCursorUp/Down with drag swap, startDrag/stopDrag/toggleDrag, getOrderedItem, render with drag/cursor/normal styles; optional Block wrapper
- [x] **tests/reorderable_list_test.zig** — ReorderableList tests (initialization, navigation, drag mode, order swap, getOrderedItem, render, edge cases) — 40+ tests
- [x] Export modules via tui.zig
- [x] Add tests to build.zig
- [x] Release v2.24.0

**Success Criteria**:
- MultiSelectList: selections[] slice mirrors toggle operations; countSelected tracks state; symbols render in correct positions
- ReorderableList: order[] is rewritten by drag operations; cursor follows the dragged item; non-drag navigation does not swap
- Both widgets handle empty items[], single-item lists, and zero-area Rect without crash

### v2.23.0 — Form Widget with Multi-field Input & Validation (Target: 2026-07-05)

**Theme**: Reusable form widget for multi-field input forms with focus navigation and validation

**Checklist**:
- [x] **src/tui/form.zig** — Form: focusNext/focusPrev/focusField/getFocusedId/isFocused/validateAll/isValid/render; FormField (id, label, placeholder, required, focusable, validate); FieldState (value, error_msg); ValidateFn type
- [x] **tests/form_test.zig** — Form tests (initialization, focus navigation, skip non-focusable, validateAll, isValid, render to Buffer, edge cases: zero fields, all non-focusable, placeholder bug fixed) — 35 tests
- [x] Export form module via tui.zig
- [x] Add form_tests to build.zig
- [x] Release v2.23.0

**Success Criteria**:
- focusNext/focusPrev wrap around and skip non-focusable fields
- focusField("id") finds by ID; returns false for unknown ID
- validateAll runs required check then custom validator; sets error_msg
- isValid returns false when any error_msg is non-null
- render writes label+colon+value on each row; error_msg on next row if show_errors
- Zero-area, zero-field, and all-non-focusable cases handled without crash

**Notes**:
- No allocator in Form — caller provides fields/states slices
- ValidateFn is a simple function pointer: `*const fn([]const u8) ?[]const u8`
- Placeholder shown when value is empty (fixed from initial implementation)
- Bug fixed: test used "test@" which passes validateEmail; changed to "noemail"

### v2.22.0 — Multi-Pane Workspace Layout (Target: 2026-06-28)

**Theme**: Flexible multi-pane layout manager with focus tracking and keyboard navigation

**Checklist**:
- [x] **src/tui/workspace.zig** — Workspace: flex-based multi-pane layout with focus management (focusNext/focusPrev/focusPane), renderDividers for pane separators; WorkspacePane descriptor (id, flex, min_size, focusable); WorkspaceSplit enum
- [x] **tests/workspace_test.zig** — Workspace tests (computeRects flex distribution, min_size clamping, zero-area, contiguity, focus cycling, renderDividers) — 38 tests
- [x] Export workspace module via tui.zig
- [x] Release v2.22.0

**Success Criteria**:
- computeRects distributes width/height proportionally by flex weight
- Panes respect min_size; total cannot shrink below sum of min_sizes
- focusNext/focusPrev cycle through focusable panes, skip non-focusable
- focusPane("id") finds by string ID; returns false for unknown ID
- renderDividers draws │ between horizontal panes, ─ between vertical panes
- Zero-area and single-pane edge cases handled without crash

**Notes**:
- No allocator stored in Workspace — computeRects takes allocator as arg; caller frees result
- WorkspacePane is a descriptor (no vtable, no render method) — consumer renders inside each Rect
- Designed for IDE-style layouts: file tree + editor + terminal, etc.
- Three consumer projects (zr, zoltraak, silica) can use for multi-panel dashboards

### v2.21.0 — App Shell & Status Line (Target: 2026-06-21)

**Theme**: High-level application entry point and status line infrastructure for multi-screen TUI apps

**Checklist**:
- [x] **app.zig** — AppShell: wraps ScreenRouter with AppConfig (fps_cap, exit_on_q); router() accessor
- [x] **statusline.zig** — StatusLine widget: left/center/right sections; each section accepts []Span; auto-pad to fill width; builder API (withLeft/withCenter/withRight/withStyle)
- [x] **keybinding.zig** — KeybindingMap: named action registry (register/lookup); KeybindingBar widget renders `[key] desc` pairs in a bar; KeybindingEntry nested for ergonomic access
- [x] **tests/app_shell_test.zig** — AppShell struct-level tests (init, deinit, configuration) — 12 tests
- [x] **tests/statusline_test.zig** — StatusLine tests (section render, padding, width clamping, zero-area) — 24 tests
- [x] **tests/keybinding_test.zig** — KeybindingMap tests (register, lookup, render bar) — 20 tests
- [x] Export AppShell in sailor.zig; export statusline, keybinding modules in tui.zig
- [x] Release v2.21.0

**Success Criteria**:
- AppShell.run() drives the event loop: poll event → dispatch to ScreenRouter → render top screen → flush
- AppShell handles SIGWINCH (terminal resize) by re-querying terminal size and updating layout
- StatusLine.render() fills the entire row width with left/center/right sections; center is centered
- KeybindingMap.register(action, keys, desc) stores entries; KeybindingBar renders as `[key] desc` pairs
- KeybindingMap supports context override: per-screen bindings shadow global bindings
- All handle zero-area and empty input without panic

**Notes**:
- AppShell does NOT own screen structs — caller manages screen lifetime
- StatusLine is purely presentational — no state, no allocator in render()
- KeybindingBar is designed for the bottom status line of a TUI app
- Useful for all 3 consumer projects to build clean main loops

### v2.20.0 — App Screen Manager (Target: 2026-06-14)

**Theme**: Stack-based screen navigation infrastructure for multi-screen TUI applications

**Checklist**:
- [x] **src/tui/screen.zig** — ScreenHandle: type-erased screen wrapper with vtable; ScreenResult: navigation signal (cont/pop/reset/push/replace)
- [x] **src/tui/router.zig** — ScreenRouter: allocator-backed stack navigator; push/pop/replace/reset with onEnter/onLeave lifecycle dispatch
- [x] **tests/screen_test.zig** — ScreenHandle tests (lifecycle dispatch, event routing, render, multi-type) — 12 tests
- [x] **tests/router_test.zig** — ScreenRouter tests (navigation stack, lifecycle ordering, dispatch routing, render delegation) — 24 tests
- [x] Export ScreenHandle, ScreenResult, ScreenRouter in sailor.zig; export screen/router modules in tui.zig
- [x] Release v2.20.0

**Success Criteria**:
- ScreenHandle.init(T, ptr) wraps any struct with render/handleEvent/onEnter/onLeave
- ScreenRouter.push increments depth, suspends current (onLeave), activates new (onEnter)
- ScreenRouter.pop decrements depth, leaves current, resumes previous (onEnter)
- ScreenRouter.replace swaps top screen without changing depth
- ScreenRouter.reset clears entire stack, calls onLeave on all (top-to-bottom), activates new root
- ScreenRouter.dispatch routes ScreenResult variants to corresponding navigation operations
- ScreenRouter.render delegates to top-of-stack screen only
- All edge cases (empty stack, pop-to-empty, replace on empty) handled without panic

**Notes**:
- Useful for all three consumer projects (zr, zoltraak, silica) to manage multi-screen TUI flows
- No vtable stored as local: uses Impl struct pattern for static vtable lifetime
- ScreenHandle works with both stack-allocated and heap-allocated screens
- Consumer projects can define their own screen types and compose them with ScreenRouter

### v2.19.0 — Scrollbar & Breadcrumb Navigation (Target: 2026-06-14)

**Theme**: Navigation and scroll indicator widgets for content-heavy TUI applications

**Checklist**:
- [x] **widgets/scrollbar.zig** — Scrollbar: vertical/horizontal scroll indicator with proportional thumb size/offset
- [x] **widgets/breadcrumb.zig** — Breadcrumb: navigation path display with separator, active highlighting, and left-truncation
- [x] **tests/scrollbar_test.zig** — Scrollbar tests (thumbSize math, thumbOffset math, render modes, setters, edge cases) — 62 tests
- [x] **tests/breadcrumb_test.zig** — Breadcrumb tests (totalWidth, builder pattern, render, truncation, zero-area) — 53 tests
- [x] Export Scrollbar, ScrollbarOrientation, Breadcrumb in tui.zig
- [x] Release v2.19.0

**Success Criteria**:
- Scrollbar renders correctly at any position (0..total), clamped to viewport
- Scrollbar.setPosition/setTotal update state; ratio renders track+thumb proportionally
- Breadcrumb renders `item1 / item2 / item3` with configurable separator
- Breadcrumb truncates from left when path is wider than area
- Both handle zero-area and empty input without panic

**Notes**:
- Scrollbar useful for: silica (long query results), zoltraak (key list), zr (task list)
- Breadcrumb useful for: silica (schema browser path), zoltraak (key namespace), zr (directory path)
- No allocator required in render() — all stack-based with slice input

### v2.18.0 — Layout Templates & Stepper (Target: 2026-06-07)

**Theme**: Pre-built layout helpers and multi-step wizard widget for rapid TUI development

**Checklist**:
- [x] **widgets/layout_template.zig** — DashboardLayout (header+sidebar+main+footer split), MasterDetail (two-panel with divider)
- [x] **widgets/stepper.zig** — Stepper: multi-step wizard with status tracking (pending/active/completed/failed), horizontal/vertical rendering
- [x] **tests/layout_template_test.zig** — Layout template tests (split dimensions, edge cases, zero area, offset area) — 41 tests
- [x] **tests/stepper_test.zig** — Stepper tests (navigation, status tracking, isComplete/hasFailed, rendering) — 66 tests
- [x] Export DashboardLayout, MasterDetail, Stepper, StepperStatus, StepperStep in tui.zig
- [x] Release v2.18.0

**Success Criteria**:
- DashboardLayout.split() correctly partitions area into header/sidebar/main/footer with no overlap
- MasterDetail.split() correctly splits into master/detail; render() draws divider line
- Stepper.moveNext/movePrev navigate steps with bounds clamping
- Stepper.isComplete/hasFailed query status correctly
- Both widgets handle zero-area and offset areas without panic

**Notes**:
- DashboardLayout and MasterDetail are pure layout helpers (no Buffer in split())
- Stepper uses Direction enum from layout.zig
- Useful for: zr (wizard setup flows), silica (query builder steps), zoltraak (connection wizard)

### v2.17.0 — Interactive Data Editing (Target: 2026-06-14)

**Theme**: Widgets that allow users to edit structured data inline — critical for silica (query result editing), zoltraak (Redis hash editing), and zr (config editing)

**Checklist**:
- [x] **widgets/editable_table.zig** — EditableTable: inline cell editing with row/col cursor, edit mode, row CRUD
- [x] **widgets/record_editor.zig** — RecordEditor: key-value record editor with field navigation and validation
- [x] **tests/editable_table_test.zig** — EditableTable tests (cursor nav, edit mode, confirm/cancel, render) — 42 tests
- [x] **tests/record_editor_test.zig** — RecordEditor tests (field nav, edit, validation callback, render) — 47 tests
- [x] Export both widgets in tui.zig
- [x] Release v2.17.0

**Success Criteria**:
- EditableTable renders table with cursor highlight on selected cell
- EditableTable enters edit mode on cell; renders input box in cell area
- EditableTable confirms edit on Enter, cancels on Escape
- EditableTable navigates rows/cols with arrow keys (state machine)
- RecordEditor renders key-value pairs with cursor on active field
- RecordEditor enters edit mode for value; renders inline input
- RecordEditor calls validation callback and shows error style on invalid input
- Both handle zero-area and edge cases without panic

**Notes**:
- No allocator in render() — caller provides field slices and edit buffer
- EditableTable extends Table display pattern but adds cursor + edit state
- RecordEditor is simpler: fixed fields, edit one value at a time
- Both useful for silica (SQL row editing), zoltraak (hash field editing), zr (config editing)

### v2.16.0 — Diff Viewer & JSON Browser (Target: 2026-06-07)

**Theme**: Developer-tool widgets for visualizing code diffs and structured data (JSON/YAML trees)

**Checklist**:
- [x] **widgets/diff_viewer.zig** — DiffViewer: unified diff rendering with color-coded line types
- [x] **widgets/json_browser.zig** — JsonBrowser: collapsible JSON tree with cursor navigation
- [x] **tests/diff_viewer_test.zig** — DiffViewer tests (classify, render, scroll, h_scroll, counts)
- [x] **tests/json_browser_test.zig** — JsonBrowser tests (collapse, navigate, render, styles)
- [x] Export both widgets in tui.zig
- [x] Release v2.16.0

**Success Criteria**:
- DiffViewer classifies all unified diff line kinds correctly (diff_header, file_header, hunk_header, removed, added, context, no_newline)
- DiffViewer renders with color-coded styles per line kind (red/green/cyan/bold)
- DiffViewer supports vertical and horizontal scroll without allocation
- JsonBrowser renders flat node list with depth-based indentation
- JsonBrowser collapse/expand hides subtrees (matching close bracket included)
- JsonBrowser moveDown/moveUp correctly skip hidden (collapsed) nodes
- Both widgets handle zero-area and edge cases without panic

**Notes**:
- DiffViewer: useful for silica (schema migration diffs), zoltraak (config diffs), zr (build output diffs)
- JsonBrowser: useful for silica (query result inspection), zoltraak (Redis JSON values), zr (config browser)
- No allocator in render() — caller provides the node slice for JsonBrowser
- DiffViewer: no allocation at all — iterates the raw diff string line-by-line
- classifyLine() and DiffViewerLineKind exported as top-level helpers for consumers

### v2.15.0 — Dependency Graph & Pipeline Visualization (Target: 2026-06-07)

**Theme**: Graph and pipeline widgets for dependency visualization and CI/build status display

**Checklist**:
- [x] **widgets/dag.zig** — DagWidget: directed acyclic graph with nodes as boxes, edges as lines
- [x] **widgets/pipeline.zig** — Pipeline: linear stage display with status indicators
- [x] **tests/dag_test.zig** — 36 tests for DagWidget (node creation, rendering, edge handling, clipping)
- [x] **tests/pipeline_test.zig** — 45 tests for Pipeline (status queries, rendering, layout directions)
- [x] Export both widgets in tui.zig
- [x] Release v2.15.0

**Success Criteria**:
- DagWidget renders nodes as boxes with labels, edges as connecting lines
- Pipeline renders `[icon label]` with status-appropriate icons: ✓ ✗ ⊙ · ⊘
- `isComplete()` / `hasFailed()` / `countByStatus()` work correctly
- Both widgets handle zero-area and out-of-bounds safely (no panic)

**Notes**:
- Useful for zr (task dependency graphs), silica (schema relations), zoltraak (monitoring)
- No allocator required in render() — all stack-based
- Edges draw horizontal lines with '>' arrow; vertical offset draws '|' stub

### v2.14.0 — Fuzzy Search & Command Palette (Target: 2026-06-05)

**Theme**: Command palette and fuzzy search infrastructure for all consumer projects

**Checklist**:
- [x] **fuzzy.zig** — Core fuzzy matching algorithm (scoring, highlight positions, no-alloc)
- [x] **widgets/command_palette.zig** — Modal command palette with fuzzy search, keyboard nav, categories
- [x] **widgets/filterable_list.zig** — List widget with built-in real-time fuzzy filtering
- [x] **tests/fuzzy_test.zig** — Comprehensive tests for fuzzy matching engine (34 tests)
- [x] **tests/command_palette_test.zig** — Command palette tests (register, search, activate) (38 tests)
- [x] **tests/filterable_list_test.zig** — FilterableList tests (filter, highlight, score sort) (52 tests)
- [x] Export new types in sailor.zig

**Success Criteria**:
- FuzzyMatcher scores "src" higher for "source" than for "secret" (positional bonus)
- CommandPalette can register commands and filter by fuzzy query
- FilterableList renders highlighted match positions in list items
- All 3 new modules tested with 20+ tests each
- No breaking changes to existing APIs

**Notes**:
- FuzzyMatcher is allocation-free for match operations (scores fit in stack buffer)
- CommandPalette builds on existing Block/Input/List widgets
- Both consumer-facing: silica (SQL command search), zoltraak (redis command palette)

### v2.2.0 — Consumer Feedback & Bug Fixes (Target: 2026-05-15)

**Theme**: Address real-world usage feedback from zr, zoltraak, silica migrations

**Checklist**:
- [ ] **Monitor consumer migrations**: Track progress of v2.4.0-v2.9.0 migrations
  - zr#58, zr#59, zr#60, zr#61: v2.6.0, v2.7.0, v2.8.0, v2.9.0 migrations (2026-05-04, 2026-05-07, 2026-05-10, 2026-05-12)
  - zoltraak#33, zoltraak#34, zoltraak#35, zoltraak#36, zoltraak#37, zoltraak#38: v2.4.0-v2.9.0 migrations
  - silica#44, silica#45, silica#47, silica#48: v2.6.0, v2.7.0, v2.8.0, v2.9.0 migrations (2026-05-04, 2026-05-07, 2026-05-10, 2026-05-12)
  - Help resolve any migration blockers
  - Document common migration patterns
- [ ] **Bug fixes**: Fix any issues discovered during real-world usage
  - Prioritize bugs from consumer projects (`from:*` labels)
  - Quick turnaround on critical issues
  - Comprehensive test coverage for fixes
- [ ] **Documentation improvements**: Based on consumer questions
  - Add examples for common use cases
  - Clarify API documentation where confusion occurs
  - Migration guides for tricky patterns
- [ ] **API refinements**: Minor improvements based on usage patterns
  - Add missing convenience methods if requested
  - Improve error messages
  - No breaking changes

**Success Criteria**:
- All consumer projects successfully migrated to latest sailor
- Zero critical bugs in production use
- Positive feedback from consumer maintainers
- Documentation addresses common questions

**Notes**:
- Reactive milestone — scope adjusts based on consumer feedback
- May release earlier if migrations complete smoothly with no issues
- Focus: stability, usability, developer experience

## Completed Milestones

| Version | Name | Date | Summary |
|---------|------|------|---------|
| v2.14.0 | Fuzzy Search & Command Palette | 2026-05-31 | FuzzyMatcher (greedy subsequence, prefix/consecutive/word-boundary/camelCase bonuses, score 0.0-1.0, static 512-slot buffer, case-insensitive, 34 tests), CommandPalette widget (register/setQuery/getSelected/activate/render, category search, score-sorted results, 38 tests), FilterableList widget (setItems/setFilter/clearFilter/getSelected/render, match position tracking, fuzzy-sorted display, 52 tests). Total: +124 tests (~4828+ passing), 0 breaking changes. Consumer migrations: zr, zoltraak, silica |
| v2.13.0 | Store Middleware & Async Actions | 2026-05-29 | MiddlewareStore pipeline (Logger middleware, subscriber notifications, 19 tests), ThunkStore async dispatch (dispatchThunk, context access, error propagation, 23 tests), UndoStore time-travel (undo/redo with configurable history depth 50, canUndo/canRedo, 23 tests), StatePersist serialization (save/load via pluggable encode/decode fns, round-trip, 22 tests), ReactiveList widget (auto-bound to Signal, render callback, 20 tests). Total: +107 tests (~4700+ passing), 0 breaking changes. Consumer migrations: zr, zoltraak, silica |
| v2.12.0 | Reactive State Management | 2026-05-28 | Signal(T) mutable reactive values with subscriber callbacks (subscribe/unsubscribe/batch), Computed(T,S) read-only derived values via lazy evaluation, Effect(T) side effect callbacks, Scope.batch() deferred notifications, Store(State,Action) centralized state with reducer pattern (dispatch/subscribe), ReactiveGauge/ReactiveText/ReactiveCounter widgets auto-bound to signals. Total: +89 tests (signal_test:24, store_test:19, reactive_test:46), ~4600+ total passing, 0 breaking changes. Consumer migrations: zr, zoltraak, silica |
| v2.11.0 | Extended Graphics & Protocol Support | 2026-05-27 | Sixel encoder/decoder, color palette optimization, animation support, SixelCompressor. Kitty protocol (transmit/display/delete, unicode placeholder, z-index, KittyImageManager). ANSI art rendering (block/braille/ascii algorithms, dithering, real-time video conversion, AnsiArtPlayer). Advanced effects: gradient backgrounds, blur/transparency, custom borders, particles, transitions. image_renderer.zig (unified protocol selector). Total: +200+ tests (~4600 passing), 6 cross-platform targets, 0 breaking changes. Consumer migrations: zr, zoltraak, silica |
| v2.10.2 | Natural Language Commands Bug Fixes | 2026-05-18 | PATCH: Fixed Zig 0.15 API compatibility in natural_language_commands (tokenizeScalar, BoundedArray→manual tracking, toOwnedSlice allocator), rewrote 59 meaningless tests with actual API validation (CommandParser intent verification). Zero functional changes, zero breaking changes. Test health: 4426/4478 passing (98.8%). Consumer migrations: None (optional patch) |
| v2.10.1 | Test Reliability Improvements | 2026-05-16 | PATCH: Fixed timing-sensitive tests (advanced_profiler 5µs→10ms sleep, sanity checks vs strict assertions), documented llm_client HTTP mocking limitations (12 tests skipped, anyopaque-based injection constraints). Zero functional changes, zero breaking changes. Test health: 4426/4478 passing (98.8%). Consumer migrations: None (optional patch) |
| v2.10.0 | AI/ML Integration & Smart Features | 2026-05-13 | LLM Integration Layer (TokenBudget, RateLimiter, PromptTemplate, ResponseStreamWidget, LlmClient with streaming, 38/50 tests passing), Smart Autocomplete (context-aware CompletionContext, multi-source aggregation LocalSource/LlmSource/PatternSource, pattern learning, semantic ranking, ghost text preview, 52 tests), Layout Intelligence (LayoutAnalyzer tree traversal, constraint suggestions, responsiveness checking, accessibility recommendations, performance analysis, 52 tests), Natural Language Commands (CommandParser with 11 intents, context-aware disambiguation, command history with semantic search, tutorial mode, 59 tests). Total: +198 tests (~4426 passing), 6 cross-platform targets, 0 breaking changes. Consumer migrations: zr#64, zoltraak#41, silica#51 |
| v2.9.0 | Developer Experience & Debugging Tools | 2026-05-12 | Live Widget Inspector (hierarchical tree view, real-time property inspection, focus tracking, memory/render metrics, 55 tests), Advanced Profiling (widget flamegraphs, event traces, layout visualization, memory heatmaps, Chrome DevTools export, 38 tests), Error Recovery & Resilience (render error boundaries, auto-recovery, error hooks, graceful degradation, test utilities, 58 tests), Developer Console (Zig expression eval, CSS-like query language, state mutation, screenshot/recording, Ctrl+Shift+D, REPL with history/undo, 40 tests). Total: +191 tests (~4200 passing), 6 cross-platform targets, 0 breaking changes. Inspired by React DevTools, Chrome DevTools, Elm debugger. Consumer migrations: zr#61, zoltraak#38, silica#48 |
| v2.8.0 | Cross-Platform Improvements | 2026-05-10 | Windows Console API (ConPTY integration, legacy fallback, ANSI emulation, UTF-16 encoding), Platform-specific optimizations (Linux zero-overhead ANSI, macOS Metal detection, Windows batch console API), CI enhancements (Windows/macOS/Linux native tests, platform-specific test suites), Documentation (platform-specific setup guides, terminal compatibility matrix), Testing (27 Windows console tests, platform quirks tests, UTF-16 tests). Total: ~4130 passing tests (+27), 6 cross-platform targets, 0 breaking changes. Consumer migrations: zr#60, zoltraak#37, silica#47 |
| v2.7.0 | Event System & Async Integration | 2026-05-07 | Event Bus (publish-subscribe pattern, filtering, transformation, scoped subscriptions, thread-safety, 48 tests), Command Pattern (undo/redo, BatchCommand, compression, 29 tests), Async Task Runner (cooperative multitasking, priority queue, cancellation, progress tracking, 21 tests), Event Debouncing & Throttling (zero-allocation rate limiting, 25 tests). Total: +123 tests (~4100 passing), 6 cross-platform targets, 0 breaking changes. Consumer migrations: zr#59, zoltraak#36, silica#45 |
| v2.6.0 | Advanced Input & Clipboard | 2026-05-04 | Multi-line TextArea (line wrapping WrapMode, selection support, syntax highlighting hooks, +31 tests), Clipboard operations (ClipboardHistory FIFO buffer, SystemClipboard cross-platform integration macOS/Linux/Windows, OSC 52 support, +71 tests), Input validation framework (email/URL/phone validators, regex, min/max length, visual feedback, async support, +79 tests), Autocomplete enhancements (fuzzy matching, context-aware suggestions, multi-column popup, docs preview, +23 tests). Total: +204 tests (~3900 passing), 6 cross-platform targets, 0 breaking changes |
| v2.5.0 | iTerm2 Protocol & Unicode Grapheme Support | 2026-05-03 | iTerm2 inline images (OSC 1337, 19 tests), Unicode grapheme clusters (UAX#29, 15 tests), Terminal quirks database (8 quirks, 25 tests), Benchmark stability tests (variance < 5%, 8 tests), CI regression detection (10% threshold). Total: +67 tests (~3816 passing), 6 cross-platform targets verified, 0 breaking changes |
| v2.4.0 | Testing Infrastructure & Quality Tooling | 2026-04-29 | Snapshot testing (SnapshotRecorder/Matcher with auto-update, 38 tests), Property-based testing (Generator with seed-based determinism, PropertyTest runner, 38 tests), Visual regression (VisualDiff, SideBySideComparison, 23 tests), Mock Terminal (programmable terminal with event injection, output capture, 17 tests), Testing utilities (LeakCheckAllocator, WidgetFixture, assertion helpers, benchmark tools, 47 tests). Total: +163 tests (3691 passing), 0 breaking changes |
| v2.3.0 | Advanced Widget Features | 2026-04-27 | Scrollable widgets (Table/List vertical+horizontal scroll, Paragraph justify+indent), State persistence (Table/List/Input state save/restore, StateHistory undo/redo), Advanced styling (gradient backgrounds v121, border styles single/double/thick/rounded/dashed v125, shadow effects drop/inner/box v125), Widget composition (Bordered/Padded/Scrollable wrappers), Performance (LazyBuffer, VirtualList, RenderBudget). All tests passing, 0 breaking changes |
| v2.1.0 | Performance & Ergonomics Polish | 2026-04-19 | Performance optimizations: Buffer diff +38% (row-level skipping), Buffer fill +34% (direct array access), Buffer set +33% (eliminated bounds checks). API ergonomics: Rect.fromSize(), Constraint/Color/Span/Line constructors, semantic constants (Style.bold/dim/italic, Color.red/green/yellow). 1036 tests passing, 6 cross-platform targets verified, 0 breaking changes |
| v2.0.0 | Major Release: API Cleanup & Modernization | 2026-04-13 | BREAKING CHANGES: Removed Buffer.setChar() (use Buffer.set()), removed Rect.new() (use struct literals). Kept Block.withTitle() as valid builder pattern. Migration script updated. All tests passing (~3345 tests). Clean API, simplified naming, better ergonomics |
| v1.38.1 | Migration Script Fixes & Test Coverage | 2026-04-07 | Patch release: migration script diff exit code handling fix, TextArea widget comprehensive tests (+~50 tests), Tree widget comprehensive tests (+~50 tests) — ~3345 total tests, 0 breaking changes |
| v1.38.0 | v2.0.0 Migration Tooling & Automation | 2026-04-07 | Migration script (automated sed/regex patterns for Buffer/Style/Widget API changes), deprecation audit (all v2.0.0 changes have warnings), migration testing framework (before/after test cases), consumer project dry-run validation (zr/zoltraak/silica) — ~3245 total tests (+50), 0 breaking changes, prepares for v2.0.0 |
| v1.37.0 | v2.0.0 Deprecation Warnings & Bridge APIs | 2026-04-07 | deprecation.zig (compile-time warnings: warn/replace/param/type_/field helpers, +10 tests), Buffer.set() alongside setChar() (v2.0.0 naming with deprecation warnings, +3 tests), Style inference helpers (withForeground/Background/Colors, makeBold/Italic/Underline/Dim chaining methods, +16 tests), Widget lifecycle standardization (removed unnecessary init() from stateless widgets, fixed ArrayList API, +31 lifecycle tests), v1-to-v2-migration.md guide (451 lines: comprehensive migration patterns, sed scripts, side-by-side examples), migration_demo.zig (210 lines: full API comparison demo) — ~3245 total tests (+60), 0 breaking changes |
| v1.36.0 | Performance Monitoring & Real-Time Metrics | 2026-04-06 | render_metrics.zig (widget render time tracking: min/max/avg/p50/p95/p99, +31 tests), memory_metrics.zig (allocation tracking: peak/current bytes, +25 tests), event_metrics.zig (event latency tracking: queue depth, +39 tests), MetricsDashboard widget (3 layout modes: vertical/horizontal/grid, color-coded warnings, +44 tests), performance regression tests (+4 tests: Block/Event/Memory/Aggregation), metrics_dashboard.zig example — 3162 total tests (+143), 0 breaking changes |
| v1.35.0 | Widget Accessibility & Keyboard Navigation | 2026-04-05 | ARIA attributes (aria.zig: 30+ roles, 8 state flags, screen reader announcements, AriaWidget mixin, +31 tests), Focus trap (focus_trap.zig: modal focus containment, FocusTrapStack for nested dialogs, +25 tests), Standard keyboard shortcuts (keybindings.zig: Ctrl+C/X/V copy/cut/paste, Ctrl+Z/Y undo/redo, Ctrl+A select all, +7 tests), accessibility_demo.zig — 3,022 total tests (+63), 0 breaking changes, 6 cross-platform targets verified |
| v1.34.0 | Terminal Clipboard & System Integration | 2026-04-04 | OSC 52 clipboard API (write operations, 3 selection types), terminal emulator detection (xterm/kitty/iTerm2/WezTerm/Alacritty/Windows Terminal), terminal capability detection (truecolor/mouse/clipboard/bracketed paste), paste bracketing enhancements (PasteHandler/PasteReader, multi-line paste with LF/CRLF/CR support), clipboard_demo.zig example — 2901 total tests (+38 from paste.zig), 0 breaking changes |
| v1.33.0 | Specialized Widgets & Components | 2026-04-04 | 6 specialized widgets: LogViewer, MetricsPanel, ConfigEditor, SplitPane, Breadcrumb, Tooltip — NEW: Tooltip widget with 5 positioning strategies (above/below/left/right/auto), smart boundary detection, arrow indicators (▲▼◀▶), builder pattern API — ~2,516 total tests (+53), 0 breaking changes, auto-release executed |
| v1.32.0 | Advanced Layout Features | 2026-04-03 | Nested Grid layouts (grid-within-grid, auto-sizing), Aspect ratio constraints (maintain 16:9/4:3 proportions), Min/max size propagation (4 enforcement strategies), Auto-margin/padding (symmetric/all helpers, underflow protection), Layout debugging inspector (tree visualization, splitDebug/print), dashboard_advanced.zig example — 3478 total tests (+91), 0 breaking changes |
| v1.31.0 | Performance Profiling & Optimization Tools | 2026-04-02 | Render profiler enhancements (flame graphs, beginScope/endScope, +6 tests), Memory allocation tracker (hot spots, leak detection, +10 tests), Event loop profiler (latency, percentiles p95/p99, +10 tests), Widget performance metrics (cache hit rates), Profiling demo (profile_demo.zig), Optimization guide (docs/optimization.md) — 3437 total tests, 0 breaking changes |
| v1.30.0 | Error Handling & Debugging Enhancements | 2026-04-01 | Debug logging system (debug_log.zig, SAILOR_DEBUG env var, 13 tests), stack trace helpers (stack_trace.zig, assert/require/ensure, 10 tests), error recovery examples (error_handling_demo.zig), enhanced error context (error_context.zig), validators (validators.zig) — 3405 total tests, 0 breaking changes |
| v1.29.0 | Documentation Completion | 2026-04-01 | API documentation 99.9% complete (1376/1378 functions, +25 from v1.28.0), documented: sixel.zig (2), budget.zig (3), test_utils.zig (4), session.zig (4), debugger.zig (5), notification.zig (2), particles.zig (6), terminal.zig (5) |
| v1.28.0 | Ecosystem Integration & Polish | 2026-04-01 | zuda integration audit (no changes needed), 12 widget performance benchmarks (all <0.02ms/op, 228× faster than 60 FPS), v2.0.0 RFC planning (breaking changes, timeline: May-June 2026), 0 consumer issues |
| v1.27.0 | Documentation & Examples | 2026-03-31 | API documentation 98% complete (1351/1378 functions), 3 comprehensive guides (getting-started, troubleshooting, performance), 5 new example apps (hello, counter, dashboard, task_list, layout_showcase) |
| v1.26.0 | Testing & Quality Assurance | 2026-03-29 | Memory leak audit & fixes (Tree, Form), 292 new tests (termcap +37, pool +17, bench +12, repl +8, docgen +7, transition +32, timer +35, menu +50, form +30, chunkedbuffer +28, richtext_parser +38, 13 leak tests), total 3393 tests |
| v1.25.0 | Form & Validation | 2026-03-28 | Form widget, 15+ validators (basic, numeric, pattern), input masks (SSN, phone, date), inline error display, field focus navigation, form_demo.zig example |
| v1.24.0 | Animation & Transitions | 2026-03-27 | Animation trait, transition helpers (fade, slide, expand), Timer system, 22 easing functions (cubic, elastic, bounce, back, circ, expo), animation_demo.zig |
| v1.23.0 | Plugin Architecture & Extensibility | 2026-03-27 | Widget trait system, renderer hooks, theme plugin (JSON), composition helpers (Padding/Centered/Aligned/Stack/Constrained), plugin demo example (+10 tests) |
| v1.22.0 | Rich Text & Formatting | 2026-03-26 | SpanBuilder/LineBuilder, markdown parser, line breaking, text measurements (+123 tests) |
| v1.21.0 | Streaming & Large Data | 2026-03-25 | DataSource abstraction (Item/Table/Line), large data benchmarks (1M items, 100MB+) |
| v1.20.0 | Quality & Completeness | 2026-03-25 | Windows Unicode tests (23), pattern docs, docgen dir scanning, error context, edge hardening |
| v1.19.0 | CLI Enhancements & Ergonomics | 2026-03-24 | Arg groups, color themes, table formatting, progress templates, env config |
| v1.18.0 | Developer Experience & Tooling | 2026-03-21 | Hot reload for themes, widget inspector, benchmark suite, example gallery, documentation generator |
| v1.17.0 | Widget Ecosystem Expansion | 2026-03-19 | Menu, Calendar, FileBrowser, Terminal, Markdown widgets |
| v1.16.0 | Advanced Terminal Features & Protocols | 2026-03-17 | Terminal capability database, bracketed paste, synchronized output, hyperlinks, focus tracking |
| v1.15.0 | Technical Debt & Stability | 2026-03-16 | Thread safety fixes, XTGETTCAP implementation, platform-specific tests, memory leak audit, multi-platform CI |
| v1.14.0 | Performance & Memory Optimization | 2026-03 | Memory pooling, render profiling, virtual rendering, incremental layout, buffer compression |
| v0.1.0 | Terminal + CLI Foundation (Phase 1) | 2026-02 | term.zig, color.zig, arg.zig, 102 tests |
| v0.2.0 | Interactive (Phase 2) | 2026-02 | repl.zig, progress.zig, fmt.zig |
| v0.3.0 | TUI Core (Phase 3) | 2026-02 | style, symbols, layout, buffer, tui core, 96 tests |
| v0.4.0 | Core Widgets (Phase 4) | 2026-02 | Block, Paragraph, List, Table, Input, Tabs, StatusBar, Gauge |
| v0.5.0 | Advanced Widgets (Phase 5) | 2026-02 | Tree, TextArea, Sparkline, BarChart, LineChart, Canvas, Dialog, Popup, Notification |
| v1.0.0 | Polish (Phase 6) | 2026-02 | Theming, animations, benchmarks, examples, docs |
| v1.1.0 | Accessibility & Internationalization | 2026-03 | Screen reader hints, focus management, Unicode width (CJK/emoji), RTL text |
| v1.2.0 | Layout & Composition | 2026-03 | Grid layout, ScrollView, overlay/z-index, split panes, responsive breakpoints |
| v1.3.0 | Performance & Developer Experience | 2026-03 | RenderBudget, LazyBuffer, EventBatcher, DebugOverlay, ThemeWatcher |
| v1.4.0 | Advanced Input & Forms | 2026-03 | Form widget, Select/Dropdown, Checkbox, RadioGroup, input validators |
| v1.5.0 | State Management & Testing | 2026-03 | Event bus, Command pattern, MockTerminal, snapshot testing, example test suite |
| v1.6.0 | Data Visualization & Advanced Charts | 2026-03 | Heatmap, PieChart, ScatterPlot, Histogram, TimeSeriesChart |
| v1.7.0 | Advanced Layout & Rendering | 2026-03 | FlexBox, viewport clipping, shadow/border effects, custom widget traits, layout caching |
| v1.8.0 | Network & Async Integration | 2026-03 | HTTP client widget, WebSocket widget, async event loop, TaskRunner, LogViewer |
| v1.9.0 | Developer Tools & Ecosystem | 2026-03 | WidgetDebugger, PerformanceProfiler, CompletionPopup, ThemeEditor, Widget Gallery |
| v1.10.0 | Mouse & Gamepad Input | 2026-03 | Mouse events (SGR), widget mouse traits, gamepad/controller, touch gestures, input mapping |
| v1.11.0 | Terminal Graphics & Effects | 2026-03 | Sixel/Kitty graphics, animated transitions, particle effects, blur/transparency |
| v1.12.0 | Enterprise & Accessibility | 2026-03 | Session recording, audit logging, WCAG AAA themes, screen reader enhancements, keyboard navigation |
| v1.13.0 | Advanced Text Editing & Rich Input | 2026-03 | Syntax highlighting, code editor widget, autocomplete, multi-cursor editing, rich text input |

## Milestone Establishment Process

미완료 마일스톤이 **2개 이하**가 되면, 에이전트가 자율적으로 새 마일스톤을 수립한다.

**입력 소스** (우선순위 순):
1. `gh issue list --state open --label feature-request` — 사용자/소비자 요청 기능
2. `docs/PRD.md` — 미구현 PRD 항목
3. 소비자 프로젝트 피드백 — zr, silica, zoltraak에서 발행한 `from:*` 이슈
4. 기술 부채 — Known Limitations, TODO, 성능 병목
5. Zig 버전 업데이트 대응

**수립 규칙**:
- 마일스톤 하나는 단일 테마로 구성
- 1-2주 내 완료 가능한 범위로 스코프 설정
- 버전 번호는 마지막 마일스톤의 다음 번호로 자동 부여
- 수립 후 이 파일의 Active Milestones 섹션에 추가하고 커밋: `chore: add milestone v1.X.0`

## Dependency Tracking

### zuda Library

- **Repository**: https://github.com/yusa-imit/zuda (v1.15.0 available)
- **Migration targets**: 없음 — TUI 특화 자료구조는 sailor 자체 유지
- **zuda-first policy**: 범용 데이터 구조/알고리즘이 필요하면 zuda에서 먼저 확인 후 사용

#### TUI 특화 구조 (sailor 자체 유지)

sailor의 다음 자료구조는 TUI에 특화되어 있어 zuda로 대체하지 않는다:
- `src/tui/buffer.zig` — Cell Buffer diff 엔진
- `src/tui/layout.zig` — Layout constraint solver
- `src/tui/grid.zig` — Grid layout 알고리즘
- `src/unicode.zig` — Unicode width calculation

#### zuda-first Policy

새 기능 구현 시 **범용** 자료구조/알고리즘이 필요하면:
1. zuda에 해당 모듈이 있는지 확인 → 있으면 `build.zig.zon`에 zuda 의존성 추가 후 import
2. 없으면 → `gh issue create --repo yusa-imit/zuda --label "feature-request,from:sailor"` 발행 후 판단
3. TUI 특화 구조(위젯, 렌더링, 레이아웃)는 해당하지 않음

#### 호환성 검증 프로토콜

소비자 프로젝트(zr, zoltraak, silica)가 zuda를 도입할 때 sailor와의 호환성을 확인한다:

1. `build.zig.zon`에서 sailor + zuda 동시 의존성이 빌드 충돌 없이 동작하는지 검증
2. 모듈 이름 충돌이 없는지 확인 (sailor = "sailor", zuda = "zuda")
3. 소비자가 zuda 도입 후에도 sailor 테스트가 전체 통과하는지 확인

#### Issue Filing

```bash
# 호환성 문제
gh issue create --repo yusa-imit/zuda --label "bug,from:sailor" \
  --title "bug: compatibility issue with sailor" \
  --body "## 증상\n<문제>\n## 환경\n- sailor: <ver>\n- zuda: <ver>\n- zig: $(zig version)"

# 기능 요청
gh issue create --repo yusa-imit/zuda --label "feature-request,from:sailor" \
  --title "feat: <description>" \
  --body "## 필요한 이유\n<why>\n## 제안 API\n<usage>"
```
