# sailor — Milestones

## Current Status

- **Latest release**: v2.71.0 (2026-07-02) — SankeyDiagram Widget
- **Latest minor**: v2.71.0 (2026-07-02) — SankeyDiagram Widget
- **Next release**: v2.72.0 — TBD
- **Active milestones**: 0 pending implementation
- **Blockers**: None

### v2.71.0 — SankeyDiagram Widget (Complete)

**Theme**: A Sankey diagram widget that visualizes quantitative flows between nodes using proportional vertical bars and horizontal connectors. Nodes are grouped into columns and rendered as block-character bars whose height is proportional to their total flow. Flow connections are drawn as horizontal lines between adjacent columns. Supports focused node highlighting, customizable node width and column gap, optional block borders, and per-node/per-flow styling. Useful for energy/budget flows, network traffic visualization, user journey funnels, and any quantitative source-to-target data. MAX_NODES=32, MAX_FLOWS=64, no heap allocations.

**Checklist**:
- [x] **src/tui/widgets/sankey.zig** — SankeyDiagram: `nodes` ([]const SankeyNode=&.{}); `flows` ([]const SankeyFlow=&.{}); `focused` (usize=0); `node_width` (u16=2); `col_gap` (u16=8); `style` (Style={}); `node_style` (Style={}); `flow_style` (Style={}); `focused_style` (Style={}); `block` (?Block=null); `pub const MAX_NODES: usize = 32`; `pub const MAX_FLOWS: usize = 64`; SankeyNode (label []const u8=""; column usize=0; style Style={}); SankeyFlow (source usize=0; target usize=0; value f32=0.0; style Style={}); `init()`; `nodeCount() usize`; `flowCount() usize`; builder withNodes/Flows/Focused/NodeWidth/ColGap/Style/NodeStyle/FlowStyle/FocusedStyle/Block; `render(*Buffer, Rect)`
- [x] **tests/sankey_test.zig** — 79 tests: init/defaults, nodeCount/flowCount capping, builder immutability, render zero/minimal area, empty nodes/flows, single node, two nodes no flows, two nodes one flow, column layout, focused node styling, non-focused node styling, flow drawing, node height proportional to flow, block border, MAX_NODES/FLOWS cap, edge cases
- [x] Export SankeyDiagram, SankeyNode, SankeyFlow via tui.zig widgets struct and top-level
- [x] Add sankey_tests to build.zig
- [x] Release v2.71.0

### v2.70.0 — MatrixView Widget (Complete)

**Theme**: A 2D matrix display widget that renders numeric data as a colored heatmap grid. Each cell displays an optional value label and is colored by its magnitude using a configurable color scale. Supports row/column headers, focused cell highlighting, and optional block borders. Useful for correlation matrices, confusion matrices, distance matrices, heatmaps, and any 2D numeric data visualization. MAX_ROWS=32, MAX_COLS=32, no heap allocations.

**Checklist**:
- [x] **src/tui/widgets/matrix_view.zig** — MatrixView: `data` ([]const []const f32=&.{}); `row_headers` ([]const []const u8=&.{}); `col_headers` ([]const []const u8=&.{}); `focused_row` (usize=0); `focused_col` (usize=0); `min_val` (f32=0.0); `max_val` (f32=1.0); `cell_width` (u16=6); `show_values` (bool=true); `style` (Style={}); `header_style` (Style={}); `focused_style` (Style={}); `block` (?Block=null); `pub const MAX_ROWS: usize = 32`; `pub const MAX_COLS: usize = 32`; `init()`; `rowCount() usize`; `colCount() usize`; builder withData/RowHeaders/ColHeaders/FocusedRow/FocusedCol/MinVal/MaxVal/CellWidth/ShowValues/Style/HeaderStyle/FocusedStyle/Block; `render(*Buffer, Rect)`
- [x] **tests/matrix_view_test.zig** — 94 tests: init/defaults, rowCount/colCount capping, builder immutability, render zero/minimal area, empty data, single cell, single row, single column, multi-row multi-col, row/col headers, focused cell highlighting, value display, min/max normalization, cell_width, show_values toggle, block border, MAX_ROWS/COLS cap, edge cases
- [x] Export MatrixView via tui.zig widgets struct and top-level
- [x] Add matrix_view_tests to build.zig
- [x] Release v2.70.0

### v2.69.0 — Treemap Widget (Complete)

**Theme**: A binary partition treemap widget that displays items as proportional rectangles. Supports focused item styling, centered label rendering, optional block borders, and handles up to MAX_ITEMS=64 items without heap allocation. Aspect ratio-aware splitting: horizontal when width>=height, vertical otherwise. Style merging ensures item.style shows through default focused_style. Useful for disk usage visualization, portfolio allocation, time breakdown, and any proportional data display.

**Checklist**:
- [x] **src/tui/widgets/treemap.zig** — Treemap: items ([]const TreemapItem=&.{}); focused (usize=0); style/label_style/focused_style (Style={}); show_value (bool=false); block (?Block=null); TreemapItem (label/value/style); init(); itemCount() usize; totalValue() f32; builder withItems/Focused/Style/LabelStyle/FocusedStyle/ShowValue/Block; render(*Buffer, Rect)
- [x] **tests/treemap_test.zig** — 75 tests: init/defaults, itemCount/totalValue, builder immutability, render zero/minimal area, empty items, single item, multiple items proportional layout, focused styling, block border, labels, show_value, MAX_ITEMS cap, edge cases
- [x] Export Treemap, TreemapItem via tui.zig widgets struct and top-level
- [x] Add treemap_tests to build.zig
- [x] Release v2.69.0

### v2.67.0 — RadarChart Widget (Complete)

**Theme**: A radar/spider chart widget that plots multiple data dimensions on axes radiating from a center point, drawing a polygon through the data points. Supports multiple data series (datasets), axis labels, configurable polygon fill, and focused series highlighting. Useful for comparing multi-dimensional metrics, benchmark comparisons, skill matrices, and performance profiling displays. MAX_AXES=16, MAX_SERIES=8, no heap allocations.

**Checklist**:
- [x] **src/tui/widgets/radar_chart.zig** — RadarChart: axes ([]const []const u8=&.{}); series ([]const RadarSeries=&.{}); focused (usize=0); style (Style={}); axis_style (Style={}); focused_style (Style={}); filled (bool=false); block (?Block=null); RadarSeries (label []const u8=""; values []const f32=&.{}; style Style={}); init(); axisCount() usize; seriesCount() usize; builder withAxes/Series/Focused/Style/AxisStyle/FocusedStyle/Filled/Block; render(*Buffer, Rect)
- [x] **tests/radar_chart_test.zig** — 76 tests: init/defaults, axisCount/seriesCount capping, builder immutability, render zero/minimal area, single axis, multiple axes, axis labels, single series, multiple series, focused styling, filled polygon, block border, max axes, max series, edge cases
- [x] Export RadarChart, RadarSeries via tui.zig widgets struct and top-level
- [x] Add radar_chart_tests to build.zig
- [x] Release v2.67.0

**Success Criteria**:
- MAX_AXES = 16, MAX_SERIES = 8 (no heap allocations)
- Axes radiate from center: angle = (2π / axis_count) * i, starting from top (π/2 offset)
- Data values are 0.0–1.0 normalized; axis length = min(width, height) / 2 - 1
- Polygon vertices: for each axis i, point = center + (value[i] * axis_length) * unit_vector(angle_i)
- Connect polygon vertices with line-drawing characters (Braille or box-drawing)
- Axis lines: from center to edge, labeled at the far end
- Multiple series rendered in sequence; focused series uses focused_style

### v2.68.0 — HexEditor Widget (Complete)

**Theme**: A hex editor widget that displays binary data as both hexadecimal bytes and ASCII characters side-by-side. Shows an offset column, hex bytes in groups of 16 per row, and a printable ASCII preview. Supports focused byte/nibble highlighting, cursor navigation, read-only and edit modes, customizable group sizes, and Block border. Useful for binary file inspection, protocol analysis, memory debugging, and firmware visualization in TUI applications. MAX_BYTES=4096, no heap allocations.

**Checklist**:
- [x] **src/tui/widgets/hex_editor.zig** — HexEditor: `data` ([]const u8=&.{}); `cursor` (usize=0); `offset` (usize=0); `bytes_per_row` (u8=16); `group_size` (u8=1); `show_ascii` (bool=true); `show_offset` (bool=true); `style` (Style={}); `cursor_style` (Style={}); `modified_style` (Style={}); `block` (?Block=null); `pub const MAX_BYTES: usize = 4096`; `init()`; `byteCount() usize`; `rowCount() usize`; builder withData/Cursor/Offset/BytesPerRow/GroupSize/ShowAscii/ShowOffset/Style/CursorStyle/ModifiedStyle/Block; `render(*Buffer, Rect)`
- [x] **tests/hex_editor_test.zig** — 80 tests: init/defaults, byteCount/rowCount, builder immutability, render zero/minimal area, empty data, offset column, hex bytes layout, ASCII preview, cursor highlighting, group_size, show_ascii toggle, show_offset toggle, block border, multi-row data, MAX_BYTES capping, edge cases
- [x] Export HexEditor via tui.zig widgets struct and top-level
- [x] Add hex_editor_tests to build.zig
- [x] Release v2.68.0

**Success Criteria**:
- MAX_BYTES = 4096 (no heap allocations)
- Layout: `[offset] [hex bytes grouped] [ascii preview]`
- Offset column: 8-char hex address (e.g., `00000000`)
- Hex bytes: `XX XX XX XX  XX XX XX XX  XX XX XX XX  XX XX XX XX` (grouped by group_size with extra space between groups)
- ASCII: printable chars as-is, non-printable as `.`
- Cursor byte highlighted with cursor_style
- show_ascii=false omits the ASCII column
- show_offset=false omits the offset column

### v2.66.0 — MindMap Widget (Complete)

**Theme**: A hub-and-spoke mind map widget with root at center, left/right branch distribution, and grandchild nodes. Children of root alternate left/right by index (0→right, 1→left, 2→right, …). Each branch can have up to MAX_CHILDREN_PER_NODE sub-children placed further out in the same direction. Connecting lines use `─`, `│`, `├`, `┤`, `┐`, `┘`, `┌`, `└`. Focused node highlighted. Useful for brainstorming, concept mapping, hierarchical note-taking, and outline visualization. MAX_NODES=32, no heap allocations.

**Checklist**:
- [x] **src/tui/widgets/mindmap.zig** — MindMap: nodes ([]const MindNode=&.{}); focused (usize=0); style (Style={}); root_style (Style={}); focused_style (Style={}); node_width (u16=14); node_height (u16=3); h_gap (u16=2); block (?Block=null); MindNode (label []const u8=""; parent usize=0; style Style={}); init(); nodeCount() usize; childCount(usize) usize; builder withNodes/Focused/Style/RootStyle/FocusedStyle/NodeWidth/NodeHeight/HGap/Block; render(*Buffer, Rect)
- [x] **tests/mindmap_test.zig** — 79 tests: init/defaults, nodeCount, childCount, builder immutability, render zero/minimal area, root only, one right branch, one left branch, multiple branches, grandchildren, focused styling, left/right alternation, node_width/height/h_gap, block border, edge cases
- [x] Export MindMap, MindNode via tui.zig widgets struct and top-level
- [x] Add mindmap_tests to build.zig
- [x] Release v2.66.0

**Success Criteria**:
- MAX_NODES = 32 (no heap allocations)
- nodes[0] = root, placed at center of inner area
- Direct children of root: even index among siblings → right side, odd index → left side
- h_gap chars of space between root and branch node, and between branch and grandchild
- Grandchildren: same horizontal side as their parent branch; stacked vertically near parent's y
- Connection lines: root connects to each branch with `─` + junction chars at both ends
- Branch connects to each grandchild with `─` + junction chars
- Focused node rendered with focused_style
- Root node rendered with root_style (unless focused, then focused_style takes priority)

### v2.65.0 — FlowChart Widget (Complete)

**Theme**: A flow chart widget with grid-based node positioning, four node shapes (process=rectangle, terminal=rounded, decision=diamond, io=parallelogram), and labeled directional edge connectors. Supports focused node highlighting, customizable grid spacing, and Block border. MAX_NODES=32, MAX_EDGES=64, no heap allocations. Useful for algorithm visualization, process flows, decision trees, and workflow diagrams in TUI applications.

**Checklist**:
- [x] **src/tui/widgets/flowchart.zig** — FlowChart: nodes ([]const FlowNode=&.{}); edges ([]const FlowEdge=&.{}); focused (usize=0); style (Style={}); focused_style (Style={}); node_width (u16=12); node_height (u16=3); h_spacing (u16=4); v_spacing (u16=2); block (?Block=null); FlowNode (label/kind/col/row/style); FlowEdge (from/to/label/style); NodeKind (.process/.decision/.terminal/.io); init(); nodeCount()/edgeCount(); builder withNodes/Edges/Focused/Style/FocusedStyle/NodeWidth/NodeHeight/HSpacing/VSpacing/Block; render(*Buffer, Rect)
- [x] **tests/flowchart_test.zig** — 68 tests: init/defaults, NodeKind enum, nodeCount/edgeCount capping, builder immutability, render zero/minimal area, single process node, terminal node shape, multiple nodes, focused styling, edge connector, edge label, block border, grid spacing, all NodeKind, edge cases
- [x] Export FlowChart, FlowNode, FlowEdge, NodeKind via tui.zig widgets struct and top-level
- [x] Add flowchart_tests to build.zig
- [x] Release v2.65.0

**Success Criteria**:
- MAX_NODES = 32, MAX_EDGES = 64 (no heap allocations)
- Grid: cell_width = node_width + h_spacing, cell_height = node_height + v_spacing
- .process → `┌─...─┐` / `│label│` / `└─...─┘`; .terminal → `╭─...─╮` / `│label│` / `╰─...─╯`
- Edge arrows: ▼ (down), ▶ (right), ▲ (up), ◀ (left) at destination
- Focused node rendered with focused_style

### v2.64.0 — GanttChart Widget (Complete)

**Theme**: A project timeline Gantt chart widget that renders tasks as horizontal bars across a timeline. Each task has a name label, a start position, an end position, and an optional progress percentage that fills the bar partially. The chart auto-scales to fit all tasks within the available inner width. Focused task row is highlighted. Useful for project tracking, sprint boards, timeline visualization, and schedule displays in TUI applications.

**Checklist**:
- [x] **src/tui/widgets/gantt.zig** — GanttChart: tasks ([]const Task=&.{}); focused (usize=0); style (Style={}); bar_style (Style={}); focused_style (Style={}); complete_style (Style={}); label_width (u16=20); show_progress (bool=true); block (?Block=null); Task struct (name []const u8=""; start u16=0; end u16=0; progress u8=0; style ?Style=null); init(); taskCount() usize; builder API (withTasks/Focused/Style/BarStyle/FocusedStyle/CompleteStyle/LabelWidth/ShowProgress/Block); render(*Buffer, Rect)
- [x] **tests/gantt_test.zig** — 64 tests: init/defaults, builder immutability, taskCount, render zero/minimal area, single task, multiple tasks, focused highlight, progress fill, show_progress toggle, label truncation, auto-scaling, bar chars (█ complete, ░ pending), label_width, block border, edge cases
- [x] Export GanttChart, Task via tui.zig widgets struct and top-level
- [x] Add gantt_tests to build.zig
- [x] Release v2.64.0

**Success Criteria**:
- MAX_TASKS = 64 (comptime constant, no heap allocations)
- Bar fill chars: `█` for completed portion (progress%), `░` for remaining portion
- Each task renders on ONE line: label (left-aligned, padded/truncated to label_width) + "│" separator + bar
- Auto-scale: find max `end` across all tasks; timeline_width = inner.width - label_width - 1; each unit = timeline_width / max_end columns
- Bar spans from column `start * scale` to `end * scale` (0-indexed in timeline area)
- If show_progress=true: filled portion = bar_width * progress / 100 chars of `█`, rest `░`; if false: all `█`
- Task with optional per-task style: if style != null, use it for bar; otherwise use bar_style
- Focused task (focused index): entire row rendered with focused_style background
- No heap allocations — pure stack computation

### v2.63.0 — ActivityFeed Widget (Complete)

**Theme**: A scrollable activity feed widget showing timestamped events with actor, kind-based icons, and color coding. Each entry displays one line: icon prefix + optional timestamp + optional actor + event description. Supports five event kinds (info, success, warning, error, action) with distinct icons (·, ●, ⚠, ✗, →). Focused item is highlighted. Useful for audit logs, command history, system event monitoring, and changelog displays in TUI applications.

**Checklist**:
- [x] **src/tui/widgets/activity_feed.zig** — ActivityFeed: items ([]const Activity=&.{}); focused (usize=0); show_timestamp (bool=true); show_actor (bool=true); style (Style={}); timestamp_style (Style={}); actor_style (Style={}); focused_style (Style={}); info_style (Style={}); success_style (Style={}); warning_style (Style={}); error_style (Style={}); action_style (Style={}); block (?Block=null); Activity struct (timestamp []const u8=""; actor []const u8=""; event []const u8=""; kind Kind=.info); Kind enum (.info, .success, .warning, .error_kind, .action); init(); itemCount() usize; builder API (withItems/Focused/ShowTimestamp/ShowActor/Style/TimestampStyle/ActorStyle/FocusedStyle/InfoStyle/SuccessStyle/WarningStyle/ErrorStyle/ActionStyle/Block); render(*Buffer, Rect)
- [x] **tests/activity_feed_test.zig** — 70 tests: init/defaults, builder immutability, Kind enum, itemCount, render zero/minimal area, single item, multiple items, focused item highlight, show_timestamp toggle, show_actor toggle, kind icons (·●⚠✗→), kind styles, overflow (more items than height), scroll-to-focused, block border, edge cases
- [x] Export ActivityFeed, Activity, Kind via tui.zig widgets struct and top-level
- [x] Add activity_feed_tests to build.zig
- [x] Release v2.63.0

**Success Criteria**:
- MAX_ITEMS = 64 (comptime constant, no heap allocations)
- Kind icons: .info → "·", .success → "●", .warning → "⚠", .error → "✗", .action → "→"
- Each activity renders on ONE line: "[icon] [timestamp] [actor] event"
- If show_timestamp=false: omit timestamp column; if show_actor=false: omit actor column
- Focused item: rendered with focused_style background highlight across full row width
- Overflow: if more items than inner.height, show the window that includes focused item (scroll to keep focused visible); show last N items if focused is near end
- Kind style applied to the icon character; rest of line uses base style (or focused_style if focused)
- No heap allocations — pure stack computation

### v2.62.0 — BracketViewer Widget (Complete)

**Theme**: A tournament bracket display widget for TUI applications. Shows elimination-style brackets with rounds and matches rendered as columns. Draws connecting lines between rounds showing winner advancement. Supports winner highlighting, score display, focused match tracking, and Block border. Useful for tournament management, competition tracking, and decision-tree visualization.

**Checklist**:
- [x] **src/tui/widgets/bracket_viewer.zig** — BracketViewer: rounds ([]const Round=&.{}); focused_match (usize=0); focused_round (usize=0); style (Style={}); win_style (Style={}); focused_style (Style={}); show_scores (bool=true); block (?Block=null); Round struct (matches []const Match); Match struct (team_a []const u8; team_b []const u8; score_a i32=0; score_b i32=0; winner Winner=.none); Winner enum (.none, .a, .b); init(); totalRounds() usize; matchCount() usize; builder API (withRounds/FocusedMatch/FocusedRound/Style/WinStyle/FocusedStyle/ShowScores/Block); render(*Buffer, Rect)
- [x] **tests/bracket_viewer_test.zig** — 76 tests: init/defaults, builder immutability, totalRounds/matchCount, render zero/minimal area, single round/match, multiple rounds, winner highlighting, score display, focused match/round styling, show_scores toggle, connecting lines, block border, edge cases
- [x] Export BracketViewer, Round, Match, Winner via tui.zig widgets struct and top-level
- [x] Add bracket_viewer_tests to build.zig
- [x] Release v2.62.0

**Success Criteria**:
- MAX_ROUNDS = 8, MAX_MATCHES_PER_ROUND = 16 (comptime constants, no heap allocations)
- Column width = (inner.width - (rounds.len-1)) / rounds.len; each round gets one column, │ separators between rounds
- Each match rendered as 3 rows: team_a row, divider "───", team_b row (or 2 rows without divider if height constrained)
- Matches are evenly spaced vertically within each round column
- Connecting lines: for round r<len-1, draw │ from match center to next-round match input
- Winner: team name with win_style; loser: team name with normal style (dim if not .none)
- show_scores: append " [score_a:score_b]" to divider row
- Focused match (focused_round, focused_match): rendered with focused_style border/highlight
- No heap allocations — pure stack computation

### v2.61.0 — KanbanBoard Widget (Complete)

**Theme**: A kanban board widget for task management TUI apps. Shows labeled columns (lanes) each containing scrollable cards. Cards support title, optional description, optional tags, and priority levels (low/normal/high/critical). Focused column and card are visually highlighted. Useful for project tracking, task management, and multi-stage workflow visualization.

**Checklist**:
- [x] **src/tui/widgets/kanban.zig** — KanbanBoard: columns ([]const Column=&.{}); focused_column (usize=0); focused_card (usize=0); style (Style={}); column_style (Style={}); focused_column_style (Style={}); card_style (Style={}); focused_card_style (Style={}); block (?Block=null); Column struct (title []const u8; cards []const Card); Card struct (title []const u8; description []const u8=""; tags []const []const u8=&.{}; priority Priority=.normal); Priority enum (.low, .normal, .high, .critical); init(); builder API (withColumns/FocusedColumn/FocusedCard/Style/ColumnStyle/FocusedColumnStyle/CardStyle/FocusedCardStyle/Block); render(*Buffer, Rect)
- [x] **tests/kanban_test.zig** — 80 tests: init/defaults, builder immutability, Priority enum, render zero/minimal area, single column, multiple columns, column header with card count, focused column highlight, focused card highlight, priority indicators, description/tags display, overflow (more cards than height), block border, edge cases
- [x] Export KanbanBoard, Column, Card, Priority via tui.zig widgets struct and top-level
- [x] Add kanban_tests to build.zig
- [x] Release v2.61.0

**Success Criteria**:
- MAX_COLUMNS = 8, MAX_CARDS_PER_COLUMN = 32 (comptime constants, no heap allocations)
- Columns evenly divide the available width (separators between columns using │)
- Column header: "Title (N)" where N = card count, using column_style; focused column uses focused_column_style
- Priority indicators: "●" critical, "▲" high, "·" normal, "–" low (prepended to card title)
- Card rows: priority+title on first row; tags as "#tag1 #tag2" on second row (if any); description truncated on third row (if any)
- focused_card highlighted with focused_card_style within focused_column
- Scrolling: if more cards than available height, show cards starting from focused_card (if in focused column)
- No heap allocations — pure stack arrays

### v2.60.0 — WordCloud Widget (Complete)

**Theme**: A weighted word cloud widget that arranges words in an Archimedean spiral layout. High-weight words appear near the center, low-weight words toward the edges. Includes overlap detection with 1-char gaps, weight-based styling (bold/dim), and Block border support. Useful for tag clouds, frequency visualizations, and keyword displays in TUI applications.

**Checklist**:
- [x] **src/tui/widgets/wordcloud.zig** — WordCloud: words ([]const Word=&.{}); style (Style={}); bold_style (Style={}); dim_style (Style={}); block (?Block=null); Word struct (text []const u8; weight u8=1); init(); builder API (withWords/Style/BoldStyle/DimStyle/Block); render(*Buffer, Rect)
- [x] **tests/wordcloud_test.zig** — 59 tests: init/defaults, builder immutability, render zero/minimal area, empty words, single word, multiple words, spiral placement, overlap detection, weight-based styles, block border, edge cases (unicode, long words, offset areas)
- [x] Export WordCloud and Word via tui.zig widgets struct and top-level
- [x] Add wordcloud_tests to build.zig
- [x] Release v2.60.0

**Success Criteria**:
- MAX_WORDS = 64 (comptime constant, no heap allocations)
- Words sorted by weight descending before placement
- Archimedean spiral: theta step 0.5, r = 0.3 + theta * 0.25; x *= 2 for terminal aspect ratio
- Overlap detection: 1-char gap on same row
- Weight >= 5 → bold_style (if non-empty); weight <= 2 → dim_style (if non-empty); else style
- Zero-area / empty words: no crash
- No heap allocations — pure stack arrays [MAX_WORDS]

### v2.59.0 — StopWatch Widget (Complete)

**Theme**: A count-up stopwatch widget with lap time tracking, complementing the existing CountdownTimer. Displays elapsed time in HH:MM:SS.mmm format, running/paused state indicator, and an optional lap list showing split times and cumulative totals. Useful for benchmarking TUI workflows, timing operations, and interactive time tracking.

**Checklist**:
- [x] **src/tui/widgets/stopwatch.zig** — StopWatch: elapsed_ms (u64=0); laps ([]const u64=&.{}); running (bool=false); show_laps (bool=true); show_milliseconds (bool=true); label ([]const u8=""); style (Style={}); time_style (Style={}); lap_style (Style={}); status_style (Style={}); block (?Block=null); init(); formatTime(u64, bool) [12]u8; lastLapMs() u64; lapCount() usize; builder API (withElapsedMs/Laps/Running/ShowLaps/ShowMilliseconds/Label/Style/TimeStyle/LapStyle/StatusStyle/Block); render(*Buffer, Rect)
- [x] **tests/stopwatch_test.zig** — 67 tests: init/defaults, builder immutability, formatTime (zero, seconds, minutes, hours, ms toggle), lastLapMs (no laps, single lap, multiple), lapCount, render zero/minimal area, time display, status indicator, lap list, styles, block border, edge cases
- [x] Export StopWatch via tui.zig widgets struct and top-level
- [x] Add stopwatch_tests to build.zig
- [x] Release v2.59.0

**Success Criteria**:
- MAX_LAPS = 32 (comptime constant, no heap allocations)
- formatTime(ms, show_ms): HH:MM:SS.mmm (12 chars) or HH:MM:SS (8 chars)
- lastLapMs(): elapsed_ms - laps[laps.len-1] (if laps exist), else elapsed_ms
- lapCount() returns min(laps.len, MAX_LAPS)
- Render layout (inner area):
  - Row 0: centered time string (elapsed_ms formatted)
  - Row 1: centered status "[RUNNING]" or "[PAUSED]" using status_style
  - Row 2+: if show_laps and laps.len > 0: divider, then lap rows
  - Lap row format: "Lap N  +MM:SS.mmm  MM:SS.mmm" (split | cumulative)
  - show last min(laps.len, inner.height - 3) laps if height constrained
- Empty area / zero area: no crash
- No allocations — pure stack computation; formatTime returns [12]u8 array

### v2.58.0 — SplitText Widget (Complete)

**Theme**: A text display widget that splits content into labeled sections by a configurable delimiter. Each section is rendered vertically with optional section headers, optional divider lines between sections, and configurable text alignment. Vertical space is distributed evenly among sections. Useful for multi-section help text, changelogs, configuration panels, and any content with natural divisions (paragraphs, chapters, categories).

**Checklist**:
- [x] **src/tui/widgets/split_text.zig** — SplitText: text ([]const u8=""); delimiter ([]const u8="\n---\n"); section_headers ([]const []const u8=&.{}); style (Style={}); header_style (Style={}); divider_style (Style={}); divider_char (u21='─'); show_dividers (bool=true); alignment (Alignment=.left); block (?Block=null); init(); sectionCount() usize; builder API (withText/Delimiter/SectionHeaders/Style/HeaderStyle/DividerStyle/DividerChar/ShowDividers/Alignment/Block); render(*Buffer, Rect)
- [x] **tests/split_text_test.zig** — 60 tests: init/defaults, builder immutability, sectionCount, render zero/minimal area, single section, multiple sections (2/3/4), section headers, dividers, alignment (left/center/right), style application, block border, delimiter variants, long text wrapping, edge cases
- [x] Export SplitText via tui.zig widgets struct and top-level
- [x] Add split_text_tests to build.zig
- [x] Release v2.58.0

**Success Criteria**:
- MAX_SECTIONS = 64 (comptime limit, no heap allocations)
- Sections found by scanning text for delimiter occurrences
- sectionCount() returns number of sections (1 if no delimiter found, 0 if text is empty)
- Vertical space per section: base_h = inner.height / N; last section gets remainder
- Section i rendered at y = inner.y + sum of prior section heights
- If section_headers[i] exists, render header at section y, content starts at y+1
- If show_dividers and not last section, render divider at section y + section_height - 1
- Divider: fill inner.width chars with divider_char using divider_style
- Text wrapped at inner.width, alignment applied per line (left/center/right)
- Empty text: no crash, blank render; sectionCount() = 0
- Single section (no delimiter): full area used for text, no dividers
- Alignment: left=inner.x, center=inner.x+(inner.width-line.len)/2, right=inner.x+inner.width-line.len
- No heap allocations — uses fixed stack arrays [MAX_SECTIONS]

### v2.57.0 — RingMenu Widget (Complete)

**Theme**: A radial context menu widget that arranges selectable items in a circular ring around a central point. Items are positioned at equal angular intervals clockwise from the top, using terminal aspect ratio compensation (dx×2 for circular appearance). The selected item is highlighted with a configurable style. A center label can be shown at the ring's origin. Useful for action menus, mode selectors, and quick-access command wheels in TUI applications.

**Checklist**:
- [x] **src/tui/widgets/ring_menu.zig** — RingMenu: items ([]const []const u8=&.{}); selected (usize=0); center_label ([]const u8=""); style (Style={}); selected_style (Style={}); center_style (Style={}); radius (u8=4); block (?Block=null); init(); next(*self); prev(*self); selectedItem() ?[]const u8; builder API (withItems/Selected/CenterLabel/Style/SelectedStyle/CenterStyle/Radius/Block); render(*Buffer, Rect)
- [x] **tests/ring_menu_test.zig** — 65 tests: init/defaults, builder immutability, next/prev navigation, selectedItem, render zero/minimal area, item positioning (4/8 items), selected style, center label, block borders, radius variants, edge cases
- [x] Export RingMenu via tui.zig widgets struct and top-level
- [x] Add ring_menu_tests to build.zig
- [x] Release v2.57.0

**Success Criteria**:
- N items arranged at angles: angle_i = tau * i / N - pi/2 (clockwise from top)
- Item position: ix = cx + round(radius * cos(angle) * 2.0); iy = cy + round(radius * sin(angle))
- Positions clamped to inner area bounds
- Label centered on computed position: label_x = ix - label.len/2 (clamped)
- next() increments selected, wraps at items.len; prev() decrements, wraps from 0 to items.len-1
- next()/prev() with 0 items: no-op (no crash)
- selectedItem() returns null for empty items or selected >= items.len, else items[selected]
- radius=0: all items placed at center (overlapping)
- No allocations — pure stack computation with std.math cos/sin

### v2.56.0 — MiniMap Widget (Complete)

**Theme**: A compressed content overview widget showing which portion of a large content area is currently visible. Each rendered row represents N content lines (scale = ceil(total/height)). The viewport region is highlighted with a distinct style. Uses configurable characters for content rows vs empty rows. Useful for code editors, log viewers, and document navigation alongside the existing editor.zig and diff_viewer.zig widgets.

**Checklist**:
- [x] **src/tui/widgets/minimap.zig** — MiniMap: lines ([]const []const u8=&.{}); viewport_top (usize=0); viewport_height (usize=10); style (Style={}); viewport_style (Style={}); highlight_char (u21='▌'); empty_char (u21=' '); block (?Block=null); init(); builder API (withLines/ViewportTop/ViewportHeight/Style/ViewportStyle/HighlightChar/EmptyChar/Block); render(*Buffer, Rect)
- [x] **tests/minimap_test.zig** — 63 tests: init/defaults, builder immutability, render zero/minimal area, basic content, viewport detection, scaling algorithm, block borders, style application, edge cases
- [x] Export MiniMap via tui.zig widgets struct and top-level
- [x] Add minimap_tests to build.zig
- [x] Release v2.56.0

**Success Criteria**:
- scale = ceil(total_lines / inner.height) = (total_lines + inner.height - 1) / inner.height
- Row r represents content lines [r*scale .. min(total_lines, (r+1)*scale))
- in_viewport: content range overlaps [viewport_top .. viewport_top + viewport_height)
- has_content: any line in content range has .len > 0
- No allocations — pure stack computation
- viewport_height=0: no rows highlighted
- Empty lines array: all rows render empty_char with base style

### v2.55.0 — FlowText Widget (Complete)

**Theme**: A multi-column text flow widget. Reflows text into N configurable columns with word wrapping within each column. Useful for newspaper-style layouts, help text displays, and dashboard text panels. Each column gets an equal width slice of area with configurable gutter spacing between columns. Text fills column 1 first (line by line, word-wrapped), then column 2, etc.

**Checklist**:
- [x] **src/tui/widgets/flow_text.zig** — FlowText: text ([]const u8=""); columns (u8=2); gutter (u8=1); style (Style={}); alignment (Alignment=.left); block (?Block=null); init(); withText/Columns/Gutter/Style/Alignment/Block builder API; render(*Buffer, Rect)
- [x] **tests/flow_text_test.zig** — 80+ tests: init/defaults, builder immutability, render zero/minimal area, column layout (1/2/3 columns), word wrapping, gutter spacing, alignment (left/center/right), style, block border, text overflow, empty text, single word, long word no-space
- [x] Export FlowText via tui.zig widgets struct and top-level
- [x] Add flow_text_tests to build.zig
- [x] Release v2.55.0

**Success Criteria**:
- column_width = (inner.width - gutter * max(0, columns-1)) / max(1, columns)
- Text word-wrapped per column: split on spaces, fill line ≤ column_width chars
- Column i starts at x = inner.x + i * (column_width + gutter)
- Alignment: left=col.x, center=col.x+(col.width-line.len)/2, right=col.x+col.width-line.len
- columns=0 treated as columns=1 (safe)
- Empty text: no crash, blank render
- Long word > column_width: hard-split at column_width boundary
- No allocations (uses stack-based word scanner)

### v2.54.0 — AnimatedText Widget (Released: 2026-06-21)

**Theme**: A text widget with frame-based animation effects. Renders text with five animation styles: typewriter (characters reveal left-to-right by frame), wave (characters undulate vertically offset by position+frame), fade (brightness/visibility cycling by frame), blink (text visibility toggles per N frames), glow (alternating between base style and a bright highlight style). Caller increments frame via tick(). Useful for loading messages, splash screens, notifications, and status indicators in consumer projects.

**Checklist**:
- [x] **src/tui/widgets/animated_text.zig** — AnimatedText: AnimationStyle enum (.typewriter, .wave, .fade, .blink, .glow); text ([]const u8=""); frame (u32=0); speed (u8=4); base_style (Style={}); highlight_style (Style={}); alignment (Alignment=.left); block (?Block=null); init(); tick(); tickBy(n); reset(); visibleLength() usize; builder API (withText/AnimationStyle/Frame/Speed/BaseStyle/HighlightStyle/Alignment/Block); render(*Buffer, Rect)
- [x] **tests/animated_text_test.zig** — 92 tests: init/defaults, tick/tickBy (wrapping), reset, visibleLength, builder immutability, render (zero/minimal area), each animation style, alignment (left/center/right), block border, speed variations, frame-based char reveal/styling
- [x] Export AnimatedText via tui.zig widgets struct and top-level
- [x] Add animated_text_tests to build.zig
- [x] Release v2.54.0

**Success Criteria**:
- `tick()` increments frame with wrapping (+%= 1); `tickBy(n)` same; `reset()` sets frame=0
- `visibleLength()` for typewriter: min(text.len, (frame / max(speed,1))); else text.len
- Typewriter: only first visibleLength() chars rendered (others skipped)
- Wave: char at col i rendered at row = area.y + (frame/speed + i) % max(area.height, 1)
- Fade: alpha = (frame/speed) % (area.height*2); style dim if alpha < area.height, bright if alpha >= area.height
- Blink: visible = (frame/speed) % 2 == 0; if not visible, skip render
- Glow: char at i uses highlight_style if (i + frame/speed) % 3 == 0, else base_style
- Alignment: left=area.x, center=area.x+(area.width-text.len)/2, right=area.x+area.width-text.len
- speed=0 treated as speed=1 (div-by-zero safe)
- No allocations — pure value type

**Notes**:
- text is a borrowed slice (no allocation)
- Alignment clamped to not exceed area bounds (no underflow)
- Wave row clamped to [area.y, area.y+area.height-1]

### v2.53.0 — ProgressRing Widget (Released: 2026-06-21)

**Theme**: A circular ring-shaped progress indicator widget. Renders a ring using distance-based geometry with terminal aspect ratio compensation (dy×2.0 for circular appearance). Progress fills clockwise from 12 o'clock. Center shows auto percentage ("50%") or custom label. Five configurable aspects: filled char/style, empty char/style, label/label_style. Optional Block border integration. Builder pattern (all methods return value copies). 93 tests passing.

**Checklist**:
- [x] **src/tui/widgets/progress_ring.zig** — ProgressRing: value (f32=0.0); filled_char (u21='█'); empty_char (u21='░'); filled_style/empty_style (Style={}); label ([]const u8=""); label_style (Style={}); show_percentage (bool=true); thickness (u8=2); block (?Block=null); init(f32); setValue(*self, f32); setValueClamped(*self, f32); percentage() u8; render(*Buffer, Rect); builder API (withValue/FilledChar/EmptyChar/FilledStyle/EmptyStyle/Label/LabelStyle/ShowPercentage/Thickness/Block)
- [x] **tests/progress_ring_test.zig** — 93 tests: init/defaults, setValue/setValueClamped, percentage clamping, builder immutability, render crash-safety, ring cell detection (known geometry positions), label centering/override/style, block border, offset area, thickness variants, sequential renders
- [x] Export ProgressRing via tui.zig widgets struct and top-level
- [x] Add progress_ring_tests to build.zig
- [x] Release v2.53.0

**Success Criteria**:
- Ring geometry: outer_r = min(width/2, height) - 0.5; inner_r = max(0, outer_r - thickness*2)
- Ring condition: inner_r <= dist <= outer_r (dist uses dy*2 for aspect ratio)
- Angle: atan2(dx, -dy) normalized to [0,1] clockwise from top
- Label: label_y = inner.y + inner.height/2; label_x = inner.x + (inner.width - label.len) / 2
- Custom label takes precedence over show_percentage

**Notes**:
- No allocator — pure value type, stack-allocated percentage buffer in render()
- thickness=0: inner_r == outer_r, condition impossible → no ring cells drawn
- thickness=large: inner_r clamps to 0 → full circle drawn

### v2.52.0 — AnimatedBorder Widget (Released: 2026-06-20)

**Theme**: A border-only widget with frame-based color animation. The caller increments a frame counter via tick() and the border renders with animated colors cycling through a configurable palette. Five animation styles: rainbow (position+frame cycling), pulse (all-cells same color by frame), chase (one highlighted cell moving around perimeter), flash (alternating colors per N frames), gradient (position-based color gradient shifting with frame). Useful for highlighting active panels, drawing attention to notifications, and creating loading/progress indicators in all three consumer projects.

**Checklist**:
- [x] **src/tui/widgets/animated_border.zig** — AnimatedBorder: AnimationStyle enum (.rainbow, .pulse, .chase, .flash, .gradient); frame (u32=0); style (AnimationStyle=.rainbow); speed (u8=4); colors ([]const Color=default_colors); base_style (Style={}); title ([]const u8=""); title_style (Style={}); border_set (BoxSet=rounded); init(); tick(); tickBy(n); reset(); innerArea(Rect) Rect; render(*Buffer, Rect); builder API (withFrame/AnimationStyle/Speed/Colors/BaseStyle/Title/TitleStyle/BorderSet)
- [x] **tests/animated_border_test.zig** — 99 tests: init/defaults, tick/tickBy (wrapping), reset, innerArea (empty when ≤2, shrink by 1), builder immutability, render zero/minimal area, all 5 animation styles, title rendering, frame-based color changes, speed variations
- [x] Export AnimatedBorder via tui.zig widgets struct and top-level
- [x] Add animated_border_tests to build.zig
- [x] Release v2.52.0

**Success Criteria**:
- `tick()` wraps at u32 max using +%=; `tickBy(n)` same; `reset()` sets frame=0
- `innerArea()`: if width<=2 or height<=2 → empty Rect; else shrink by 1 on all sides
- Builder methods return value copies; originals unchanged
- Render: no-op if width<2 or height<2; draws all border cells with animation color applied
- Rainbow: color = colors[(pos + frame/speed) % colors.len] per border cell position
- Pulse: color = colors[(frame/speed) % colors.len] (all cells same color at given frame)
- Chase: one cell at (frame/speed % perimeter_len) gets colors[0]; rest get base_style
- Flash: (frame/speed) % 2 == 0 → colors[0]; else → colors[1] or base_style
- Gradient: color = colors[(pos*len/perimeter + frame/speed) % len]
- speed=0 treated as speed=1 (div-by-zero prevention)
- Title at row=area.y, col=area.x+2, truncated to width-4 chars; rendered only if title.len>0 and width>=5

**Notes**:
- No allocator — pure value type, colors slice borrowed from caller
- default_colors = [red, yellow, green, cyan, blue, magenta]
- Perimeter = 2*(width+height-2) cells (corners shared between top/right/bottom/left)

### v2.51.0 — CountdownTimer Widget (Released: 2026-06-20)

**Theme**: A visual countdown display widget showing remaining time with optional progress bar. Tracks total and remaining seconds, renders a formatted time string (HH:MM:SS or MM:SS) and optionally a filled/empty bar that shrinks as time elapses. Useful for timed prompts in zoltraak, deployment windows in zr, and query timeouts in silica.

**Checklist**:
- [x] **src/tui/widgets/countdown_timer.zig** — CountdownTimer: TimeFormat enum (.hh_mm_ss, .mm_ss, .seconds); total_seconds (u64); remaining_seconds (u64 = total_seconds); show_progress_bar (bool=true); show_total (bool=true); bar_char (u21='█'); empty_char (u21='░'); time_style/bar_filled_style/bar_empty_style (Style); block (?Block=null); init(total: u64); tick(); tickBy(n: u64); reset(); setRemaining(s: u64); isExpired(); progress() f32; formatTime(s: u64, fmt: TimeFormat, buf: *[9]u8) []const u8; contentHeight() u8; builder API (withTotalSeconds/ShowProgressBar/ShowTotal/Format/BarChar/EmptyChar/TimeStyle/BarFilledStyle/BarEmptyStyle/Block); render: block border → time row (centered "MM:SS" or "MM:SS / MM:SS") → bar row (proportional filled+empty chars)
- [x] **tests/countdown_timer_test.zig** — 106 tests: init/defaults, tick/tickBy (clamping at 0), reset, setRemaining (clamp to total), isExpired, progress (0.0 full expired, 1.0 full remaining, total=0 edge), formatTime (.hh_mm_ss .mm_ss .seconds for 0/59/60/3599/3600 seconds), contentHeight, builder immutability (all builders), render (basic, show_total on/off, bar on/off, bar styles, time styles, block border, zero area, zero seconds, full seconds, mid-progress)
- [x] Export CountdownTimer via tui.zig widgets struct and top-level
- [x] Add countdown_timer_tests to build.zig
- [x] Release v2.51.0

**Success Criteria**:
- `tick()` when remaining==0 → no-op; otherwise remaining -= 1
- `tickBy(n)` remaining = saturating_sub(remaining, n) (clamps at 0)
- `reset()` sets remaining = total_seconds
- `setRemaining(s)` clamps: if s > total_seconds, sets to total_seconds
- `isExpired()` true when remaining_seconds == 0
- `progress()` returns remaining/total as f32 (1.0 when full, 0.0 when expired); total==0 → 1.0
- `formatTime(0, .mm_ss)` → "00:00"; `formatTime(3661, .hh_mm_ss)` → "01:01:01"
- `contentHeight()` returns 1 (time row) + 1 (bar row if show_progress_bar)
- Builder methods all return value copies; original unchanged
- Render: time row centered; bar proportional (filled chars = floor(width * progress)); zero area handled without crash
- Both `show_total=false` ("MM:SS") and `show_total=true` ("MM:SS / MM:SS") format strings

**Notes**:
- No allocator — pure value type
- `formatTime` writes into caller-provided [9]u8 buffer (max "HH:MM:SS\0")
- progress() clamps to [0.0, 1.0]
- Bar fills from left: filled_chars = @as(usize, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * progress()))
- CountdownTimer.TimeFormat is a public nested enum

### v2.50.0 — Carousel Widget (Released: 2026-06-20)

**Theme**: A horizontal slide-navigation widget with page indicators (dots) and optional arrow hints. Caller renders the content area for the current slide; Carousel manages navigation state and renders indicator dots at the bottom. Supports looping (wraps from last→first and first→last) or clamping. Useful for onboarding flows, image/slide galleries, and tabbed content with large panels.

**Checklist**:
- [x] **src/tui/widgets/carousel.zig** — Carousel: items_count (usize); current (usize=0); loop (bool=true); show_indicators (bool=true); show_arrows (bool=true); indicator_active_char (u21='●'); indicator_inactive_char (u21='○'); left_arrow ([]const u8="◄"); right_arrow ([]const u8="►"); indicator_style/active_indicator_style/arrow_style (Style); block (?Block); init(count); next(); prev(); goTo(usize); isFirst(); isLast(); count(); indicatorHeight(); contentArea(Rect) Rect; builder API (withCurrent/Loop/ShowIndicators/ShowArrows/IndicatorActiveChar/IndicatorInactiveChar/LeftArrow/RightArrow/IndicatorStyle/ActiveIndicatorStyle/ArrowStyle/Block); render: block border → content area (caller renders) → indicator row (dots with arrows)
- [x] **tests/carousel_test.zig** — 80+ tests: init/defaults, next/prev (clamped and looped), goTo bounds, isFirst/isLast, count, indicatorHeight, contentArea geometry, builder immutability (all builders), render (basic, loop off clamped, indicators on/off, arrows on/off, styles, block border, zero area, zero items, single item, many items)
- [x] Export Carousel via tui.zig widgets struct and top-level
- [x] Add carousel_tests to build.zig
- [x] Release v2.50.0

**Success Criteria**:
- `next()` with loop=true and at last item → wraps to 0; loop=false → clamps at last
- `prev()` with loop=true and at first item → wraps to last; loop=false → clamps at 0
- `goTo(i)` with i >= items_count → no-op
- `isFirst()` true when current==0 or count==0
- `isLast()` true when current==items_count-1 or count==0
- `indicatorHeight()` returns 1 if show_indicators, else 0
- `contentArea(area)` returns area minus block insets minus indicator row height
- Builder methods all return value copies; original unchanged
- Render: block border → content area (empty, caller fills) → indicator row: left_arrow (if show_arrows and !isFirst or loop) + spaces + dots (active ● inactive ○) + spaces + right_arrow (if show_arrows and !isLast or loop)
- Zero area, zero items, single item all handled without crash

**Notes**:
- No allocator — items_count is just a usize, no slice
- `contentArea()` is a pure geometry function — call it before rendering slide content
- Indicator row is 1 row at bottom of inner area when show_indicators=true
- Arrow visibility with loop=false: left hidden at first, right hidden at last

### v2.49.0 — Wizard Widget (Released: 2026-06-16)

**Theme**: A multi-step flow navigation widget with step indicators, progress tracking, and navigation hints. Shows a visual progress strip (numbered circles connected by lines) with the current step highlighted, a content area below for caller-rendered step content, and optional back/next navigation hints at the bottom. Ideal for setup wizards, onboarding flows, and multi-stage forms in all three consumer projects.

**Checklist**:
- [x] **src/tui/widgets/wizard.zig** — Wizard: Step struct (title []const u8, description []const u8=""); steps ([]const Step); current (usize=0); active_step_style/inactive_step_style/title_style/description_style/nav_style (Style); show_nav_hint (bool=true); block (?Block); init(steps); nextStep(); prevStep(); goToStep(usize); isFirst/isLast(); stepCount(); currentStep() ?Step; headerHeight(); contentArea(Rect) Rect; builder API (withCurrent/ActiveStepStyle/InactiveStepStyle/TitleStyle/DescriptionStyle/NavStyle/ShowNavHint/Block); render: block border → step indicator row (●/○ circles + ─ connectors) → title row → separator → content area (left for caller) → nav hint row
- [x] **tests/wizard_test.zig** — 83 tests: init/defaults, nextStep/prevStep clamping, goToStep bounds, isFirst/isLast, stepCount, currentStep (null on empty), headerHeight, contentArea geometry, builder immutability, render (basic, styles, block border, zero area, empty steps, single step, multiple steps, nav hint on/off)
- [x] Export Wizard via tui.zig widgets struct and top-level
- [x] Add wizard_tests to build.zig
- [x] Release v2.49.0

**Success Criteria**:
- `nextStep()` from last step → no-op (clamped); from middle → current+1
- `prevStep()` from first step → no-op (clamped); from middle → current-1
- `goToStep(i)` with i >= steps.len → no-op
- `isFirst()` true when current==0 or steps is empty
- `isLast()` true when current==steps.len-1 or steps is empty
- `headerHeight()` returns 3 (step circles row + title row + separator) or 0 if no steps
- `contentArea(area)` returns area minus block border insets minus header height minus nav hint row (if show_nav_hint)
- Builder methods all return value copies; original unchanged
- Render: step indicators "● Title ─── ○ Title ─── ○ Title" spanning width, active step highlighted with active_step_style, inactive with inactive_step_style; separator line; nav hint "← Back" (left) and "Next →" (right) at bottom if show_nav_hint and not first/last respectively
- Zero area, empty steps, single step all handled without crash

**Notes**:
- No allocator — steps slice borrowed from caller
- `contentArea()` is a pure geometry function — call it before rendering step content
- nav hint row is 1 row at bottom of inner area when show_nav_hint=true
- Step indicator row uses '●' (U+25CF) for active, '○' (U+25CB) for inactive, '─' (U+2500) for connectors

### v2.48.0 — Marquee Widget (Released: 2026-06-16)

**Theme**: A horizontally scrolling text ticker widget. Text wider than the render area scrolls character by character, creating a continuous loop with a configurable separator. Useful for status bars, news feeds, and notification displays.

**Checklist**:
- [x] **src/tui/widgets/marquee.zig** — Marquee: ScrollDirection enum (left, right); text ([]const u8); offset (usize=0); speed (u8=1); separator ([]const u8=" | "); direction (ScrollDirection=.left); style (Style={}); block (?Block); init(text); tick(); reset(); textLen(); currentOffset(); builder API (withText/Offset/Speed/Separator/Direction/Style/Block); render: single-row scrolling text with wrap-around
- [x] **tests/marquee_test.zig** — 100 tests: init/defaults, textLen, currentOffset, tick (left/right directions, speed>1, wrapping), reset, builder immutability (all 7 builders), render (basic, scrolled, wrap-around, style, block border, zero area, empty text, single char, exact fit, right direction)
- [x] Export Marquee via tui.zig widgets struct and top-level
- [x] Add marquee_tests to build.zig
- [x] Release v2.48.0

**Success Criteria**:
- `textLen()` returns `text.len + separator.len` (min 1 to avoid division by zero)
- `currentOffset()` returns `offset % textLen()`
- `tick()` .left: `(offset + speed) % textLen()`; .right: `(textLen + offset - speed) % textLen()`
- Builder methods all return value copies; original unchanged
- Render fills area.width cells with chars from repeating `text + separator` cycle starting at currentOffset
- Block border reduces inner area correctly
- Zero area, empty text, all edge cases handled without crash

**Notes**:
- No allocator — text/separator slices borrowed from caller
- ScrollDirection is a public nested type inside Marquee struct
- Single-row render (one line of scrolling text regardless of area height)
- Useful for: status bars, news tickers, notification overlays

### v2.47.0 — DiffStat Widget (Released: 2026-06-16)

**Theme**: A git-diff-style statistics display showing per-file insertions/deletions with proportional colored bars (like `git diff --stat`). Shows filename, a bar chart of insertions (`+`) and deletions (`-`) scaled to bar_width, and counts. Useful for zr (package diff summaries), zoltraak (Redis key change tracking), and silica (schema migration diffs).

**Checklist**:
- [x] **src/tui/widgets/diffstat.zig** — DiffStat: DiffStatEntry (filename []const u8, insertions u32, deletions u32, binary bool); entries ([]const DiffStatEntry); max_filename_width (?u16, auto if null); bar_width (u16=20); insertion_char (u21='+'); deletion_char (u21='-'); insertion_style/deletion_style/filename_style/count_style/binary_style (Style); block (?Block); init(entries); totalInsertions(); totalDeletions(); totalFiles(); computeMaxFilenameWidth(); computeMaxChanges(); builder API (withMaxFilenameWidth/BarWidth/InsertionChar/DeletionChar/InsertionStyle/DeletionStyle/FilenameStyle/CountStyle/BinaryStyle/Block); render: filename padded + " | " + bar (proportional) + " " + count summary
- [x] **tests/diffstat_test.zig** — 77 tests: init/defaults, totalInsertions/Deletions/Files, computeMaxFilenameWidth, computeMaxChanges, builder immutability, render (basic, binary entry, proportional bars, zero insertions/deletions, all insertions, all deletions, styles, block border, truncation, edge cases: zero area, empty entries, single entry)
- [x] Export DiffStat via tui.zig widgets struct and top-level
- [x] Add diffstat_tests to build.zig
- [x] Release v2.47.0

**Success Criteria**:
- `totalInsertions()` sums all entry.insertions
- `totalDeletions()` sums all entry.deletions
- `totalFiles()` returns entries.len
- `computeMaxFilenameWidth()` returns max(len) of all entry.filename, or max_filename_width if set
- `computeMaxChanges()` returns max(insertions + deletions) across all entries (for proportional scaling)
- Bar proportions: insertion_cols = (insertions / max_changes) * bar_width; deletion_cols = (deletions / max_changes) * bar_width
- Binary entry shows "Bin" instead of +/- bar
- Builder methods return value copies, original unchanged
- Render format: `{filename:<width} | {bar} {+insertions,-deletions}`
- Zero area, empty entries, single binary entry all handled without crash

**Notes**:
- No allocator — entries slice borrowed from caller
- Binary flag overrides bar rendering with "Bin" text styled with binary_style
- Useful for: zr (package dependency diff), zoltraak (Redis key diff), silica (schema migration summary)

### v2.46.0 — Spinner Widget (Released: 2026-06-16)

**Theme**: A lightweight animated loading indicator with configurable frames (braille, dots, line, arc, arrow). Renders current animation frame with optional label, independent styles, and optional block border. Designed for showing loading/processing states in TUI apps.

**Checklist**:
- [x] **src/tui/widgets/spinner.zig** — Spinner: frames ([]const []const u8, default braille); frame (usize); label (?[]const u8); style/label_style (Style); block (?Block); withFrames/Frame/Label/Style/LabelStyle/Block builder API; tick() → frame+1; currentFrame() → frames[frame%frames.len]; render: spinner char + optional " " + label
- [x] **tests/spinner_test.zig** — 42 tests: defaults, builder immutability, currentFrame wrapping, tick progression, render (basic, label, truncation, custom frames, styles, block border, offset, edge cases)
- [x] Export Spinner via tui.zig widgets struct and top-level
- [x] Add spinner_tests to build.zig
- [x] Release v2.46.0

### v2.45.0 — KeyValueViewer Widget (Released: 2026-06-15)

**Theme**: A two-column key-value pair viewer for displaying config, record fields, and metadata. Shows keys in a left column (auto or fixed width) and values in a right column, with optional block border, row selection, custom separator, and keyboard navigation. Ideal for silica (DB record field inspection), zoltraak (Redis HGETALL display), and zr (package metadata viewing).

**Checklist**:
- [x] **src/tui/widgets/keyvalue_viewer.zig** — KeyValueViewer: Entry (key, value); KeyWidth union (auto, fixed); entries ([]const Entry); selected (?usize); offset; key_width (KeyWidth=.auto); separator ([]const u8=": "); key_style/value_style/selected_key_style/selected_value_style (Style); block (?Block); init(entries); count(); computeKeyWidth(); selectedEntry(); selectNext/Prev() clamped + scrollToSelected; scrollToSelected(visible_rows); builder API (withBlock/Selected/Offset/KeyWidth/Separator/KeyStyle/ValueStyle/SelectedKeyStyle/SelectedValueStyle); render: key padded to key_col_width + separator + value truncated
- [x] **tests/keyvalue_viewer_test.zig** — 79 tests covering init/defaults, count, computeKeyWidth (auto/fixed), selectedEntry, selectNext/Prev clamping, scrollToSelected, builder immutability, render key/sep/value columns, selected styling, fixed key width, offset pagination, edge cases (zero area, empty entries, single entry)
- [x] Export KeyValueViewer via tui.zig widgets struct
- [x] Add keyvalue_viewer_tests to build.zig
- [x] Release v2.45.0

**Success Criteria**:
- `computeKeyWidth()` .auto returns max(entry.key.len for all entries)
- `computeKeyWidth()` .fixed returns the fixed u16 value
- `selectNext()` from null → sets selected=0; from i → i+1; clamps at entries.len-1
- `selectPrev()` from null → no-op; from i → i-1; clamps at 0
- `scrollToSelected(vis)` adjusts offset so selected row is visible (sel < offset → offset=sel; sel >= offset+vis → offset=sel-vis+1)
- Builder methods all return new value copies, original unchanged
- Render: key padded to key_col_width with spaces, separator, value truncated to remaining width
- Selected row: key+sep use selected_key_style; value uses selected_value_style
- Block border reduces inner area correctly
- Zero area, empty entries, large offset all handled without crash

**Notes**:
- No allocator — entries slice borrowed from caller
- Entry and KeyWidth declared as nested types inside KeyValueViewer struct
- Useful for: silica (SQL record fields), zoltraak (Redis hash HGETALL), zr (package metadata)

### v2.44.0 — HexViewer Widget (Released: 2026-06-15)

**Theme**: A binary data viewer displaying content in classic hex dump format. Shows three columns: address (byte offset in hex), hex bytes (configurable bytes per row with group spacing), and ASCII representation (printable chars or '.'). Supports keyboard navigation (byte, row, page), optional selection highlighting in both hex and ASCII panels, configurable layout (show/hide address and ASCII columns), and block border. Ideal for silica (binary DB column inspection), zoltraak (binary Redis value debugging), and any TUI UI requiring binary data inspection.

**Checklist**:
- [x] **src/tui/widgets/hexviewer.zig** — HexViewer: data ([]const u8); offset (usize, aligned to bytes_per_row); selected (?usize); bytes_per_row (u8, default 16); group_size (u8, default 8); block (?Block); address_style/hex_style/ascii_style/selected_style (Style); show_ascii/show_address (bool); init(data); selectNext/Prev() clamped + scrollToSelected; selectNextRow/PrevRow() by bytes_per_row; pageDown/Up(rows); scrollToSelected(visible_rows); selectedByte() ?u8; byteCount() usize; totalRows() usize; full builder API; render: address | hex bytes (grouped) | ASCII panel
- [x] **tests/hexviewer_test.zig** — HexViewer tests (init defaults, selectNext/Prev clamping, selectNextRow/PrevRow, pageDown/Up, scrollToSelected, selectedByte, byteCount, totalRows, builder immutability, render address/hex/ASCII columns, selected byte highlight in both panels, group spacing, show_ascii=false/show_address=false, edge cases: zero area, empty data, single byte, data not aligned to bytes_per_row, block border) — 95 tests
- [x] Export HexViewer via tui.zig widgets struct
- [x] Add hexviewer_tests to build.zig
- [x] Release v2.44.0

**Success Criteria**:
- `selectNext()` advances selected by 1, clamps at last byte, calls scrollToSelected
- `selectPrev()` retreats selected by 1, clamps at 0, calls scrollToSelected
- `selectNextRow()` advances selected by bytes_per_row, clamps at last byte, calls scrollToSelected
- `selectPrevRow()` retreats selected by bytes_per_row, clamps at 0, calls scrollToSelected
- `pageDown(n)` advances offset by n rows (n * bytes_per_row bytes), clamps so last row is visible
- `pageUp(n)` retreats offset by n rows, clamps to 0
- `scrollToSelected(visible_rows)` updates offset so selected byte's row is always visible
- `selectedByte()` returns `data[selected.?]` or null if selected == null
- `byteCount()` returns `data.len`
- `totalRows()` returns `(data.len + bytes_per_row - 1) / bytes_per_row` (ceiling division)
- `offset` is always aligned to `bytes_per_row` boundary (multiple of bytes_per_row)
- Render shows address column as `{:08x}  ` (8 hex digits + 2 spaces)
- Render shows hex bytes: `{:02x} ` per byte; extra space between groups (every group_size bytes)
- Render shows ASCII panel: `|{chars}|` where printable ASCII shown, non-printable → '.'
- Selected byte highlighted with selected_style in hex column AND its ASCII char in ASCII panel
- `show_ascii=false` hides ASCII panel; `show_address=false` hides address column
- Zero-area, empty data, data.len not a multiple of bytes_per_row, single byte all handled without crash

**Notes**:
- No allocator — data slice borrowed from caller
- offset aligned to bytes_per_row: `offset = (offset / bytes_per_row) * bytes_per_row`
- Useful for: silica (binary BLOB inspection), zoltraak (binary Redis values), zr (binary artifact inspection)

### v2.43.0 — VirtualTable Widget (Released: 2026-06-15)

**Theme**: A high-performance table widget with virtual scrolling for large datasets. Unlike Table which renders all rows, VirtualTable only renders the visible rows (based on the area height), making it suitable for SQL results with thousands of rows, log viewers, and any dataset too large to hold in a Buffer at once. Row data is borrowed as a slice so no allocations occur during rendering.

**Checklist**:
- [x] **src/tui/widgets/virtualtable.zig** — VirtualTable: rows ([]const []const []const u8); columns ([]const Column); selected (?usize); offset (usize); header_style/row_style/selected_style (Style); column_spacing (u16); block (?Block); init(); selectNext/Prev() with offset auto-scroll; pageDown/Up(page_size); scrollToSelected(visible_rows); selectedRow() ?[]const []const u8; rowCount(); builder API; render: header row + visible slice of rows only
- [x] **tests/virtualtable_test.zig** — VirtualTable tests (init defaults, selectNext/Prev clamping + offset update, pageDown/Up, scrollToSelected, selectedRow, rowCount, builder immutability, render header + visible rows, offset pagination, edge cases: zero area, empty rows, single row, offset beyond data) — 76 tests
- [x] Export VirtualTable via tui.zig widgets struct
- [x] Add virtualtable_tests to build.zig
- [x] Release v2.43.0

**Success Criteria**:
- `selectNext()` moves selection down, clamps at last row, updates offset so selected row is always visible
- `selectPrev()` moves selection up, clamps at 0, updates offset so selected row is always visible
- `pageDown(n)` advances offset by n, clamps so last page fills the area
- `pageUp(n)` retreats offset by n, clamps to 0
- `render()` only iterates and writes the visible rows (offset..offset+visible_height), not all rows
- `selectedRow()` returns `rows[selected]` or null
- `rowCount()` returns `rows.len`
- Header row rendered above data rows using `header_style` and column headers
- Selected row rendered with `selected_style`
- column_spacing gap between adjacent columns
- Reuse `Column`, `ColumnWidth`, `Alignment` from table.zig
- Zero-area, empty rows, single row, offset at end all handled without crash

**Notes**:
- No allocator needed — rows/columns slices borrowed from caller
- Key difference from Table: only renders visible window, not all rows
- Key difference from StreamingTable: data is static slice, not a live stream
- Useful for: silica (SQL query results), zoltraak (Redis key listing), zr (dependency lists)

### v2.42.0 — TreeTable Widget (Released: 2026-06-14)

**Theme**: A hierarchical tree view combined with multi-column table layout. Each tree node has a cells array (one value per column), children can be expanded/collapsed, and the widget renders a header row plus tree-indented data rows. Ideal for database schema browsers (table/column/type), file browsers (name/size/modified), dependency trees (package/version/license), and any TUI UI requiring hierarchical tabular data.

**Checklist**:
- [x] **src/tui/widgets/treetable.zig** — TreeTableNode (cells, children, expanded); TreeTable (columns, nodes, selected, offset, block, header_style, row_style, selected_style, column_spacing, expanded/collapsed/leaf symbols, indent); init(); visibleCount(); selectNext/Prev(); builder API; render: header row + DFS-ordered tree rows with depth-based indent and expand/collapse symbols
- [x] **tests/treetable_test.zig** — TreeTable tests (init defaults, visibleCount with collapsed nodes, selectNext/Prev clamping and offset update, builder immutability, render header/rows/indent/symbols, edge cases: zero area, empty nodes, all collapsed, single node, deep nesting, block border) — 74 tests
- [x] Export TreeTable and TreeTableNode via tui.zig widgets struct
- [x] Add treetable_tests to build.zig
- [x] Release v2.42.0

**Success Criteria**:
- `visibleCount()` returns correct count: collapsed nodes hide all descendants
- `selectNext()` moves selection down, clamps at last visible row, updates offset to keep selection visible
- `selectPrev()` moves selection up, clamps at 0, updates offset
- Render shows header row using column headers and header_style
- Render shows tree rows with (depth * indent) spaces + symbol + cells[0] for first column
- Expanded branch node shows expanded_symbol (e.g. "▼ ") before cells[0]
- Collapsed branch node shows collapsed_symbol (e.g. "▶ ") before cells[0]
- Leaf node shows leaf_symbol (e.g. "  ") before cells[0]
- Remaining columns (cells[1..]) rendered at their column positions
- selected row uses selected_style; unselected rows use row_style
- Zero-area, empty nodes, all-collapsed, single node handled without crash

**Notes**:
- Reuse `Column` type from table.zig (header, width: ColumnWidth, alignment: Alignment)
- No allocator — all data is borrowed slices from caller
- Useful for: silica (schema browser), zoltraak (Redis key hierarchy), zr (dependency tree)

### v2.41.0 — ColorSwatch Widget (In Progress: 2026-06-14)

**Theme**: A grid-based color swatch palette for selecting colors. Displays colors as filled rectangular cells arranged in a configurable column layout. Supports keyboard navigation (next/prev/up/down), optional hex labels, focused selection indicator, and block border. Ideal for theme editors, color pickers, and any TUI UI requiring color selection.

**Checklist**:
- [x] **src/tui/widgets/colorswatch.zig** — ColorSwatch: init(colors); colors/labels/selected/columns/swatch_width/swatch_height fields; selectedColor(); selectNext/Prev/Right/Left/Up/Down (grid-aware, clamped); full builder API; render: fills each swatch cell with background color, shows selection marker, optional hex labels, scrolls to keep selected row visible
- [x] **tests/colorswatch_test.zig** — ColorSwatch tests (init defaults, navigation clamping, grid movement, selectedColor, builder immutability, render to Buffer, edge cases: zero area, empty colors, single color, narrow area, show_labels on/off, block border) — 71 tests
- [x] Export ColorSwatch via tui.zig widgets struct
- [x] Add colorswatch_tests to build.zig
- [x] Release v2.41.0

**Success Criteria**:
- `selectNext()` wraps from last to first; `selectPrev()` wraps from first to last
- `selectDown()` advances by `columns` rows (clamped at end); `selectUp()` retreats by `columns` (clamped at 0)
- `selectRight()` moves +1 within same row; at row end wraps to next row start
- `selectLeft()` moves -1 within same row; at row start wraps to previous row end
- `selectedColor()` returns `colors[selected]` or null if colors empty
- Render fills each cell with the cell's color as background
- Selected cell shows a '●' or border marker using selected_style
- `show_labels=true` renders hex label (e.g., `#RRGGBB`) below each swatch
- Zero-area, empty-colors, narrow-area handled without crash

**Notes**:
- No allocator needed — colors/labels slices borrowed from caller
- Useful for: theme_editor.zig companion, color_picker.zig alternative, zoltraak/silica theming

### v2.40.0 — RangeSlider Widget (In Progress: 2026-06-14)

**Theme**: Dual-handle horizontal slider for selecting a value range [low, high] within [min, max]. Positions handles proportionally on the track, shows selected range with a distinct fill character, supports focused handle highlighting, optional label, and value overlays. Ideal for TUI forms requiring bounded range selection (price filters, date ranges, etc.).

**Checklist**:
- [x] **src/tui/widgets/rangeslider.zig** — RangeSlider + FocusedHandle enum: init(); low/high/min/max/step (f64); decimal_places (u8); focused_handle (FocusedHandle); label/show_values; moveLowLeft/Right, moveHighLeft/Right (step-based, no crossing); setLow/setHigh/setRange (clamped); isLowAtMin/isHighAtMax; lowRatio/highRatio/rangeSize; full builder API; render: single-row track with proportional handle positions, selected range, optional label, optional value overlays
- [x] **tests/rangeslider_test.zig** — RangeSlider tests (init defaults, handle movement clamping/crossing prevention, setLow/setHigh/setRange clamping, ratio calculations, builder immutability, render to Buffer, edge cases: zero area, narrow area, focused handle styling, show_values on/off, label rendering, block border) — 86 tests
- [x] Export RangeSlider + FocusedHandle via tui.zig widgets struct
- [x] Add rangeslider_tests to build.zig
- [x] Release v2.40.0

**Success Criteria**:
- `moveLowRight()` cannot move low past high (handles do not cross)
- `moveHighLeft()` cannot move high below low (handles do not cross)
- `setLow(v)` clamps v to [min, high]; `setHigh(v)` clamps v to [low, max]
- `lowRatio()` / `highRatio()` return proportional position in [0.0, 1.0]
- Track renders `◄` and `►` handle chars at proportional x positions
- Selected range between handles renders with selected_char (e.g., `═`)
- Unselected portions outside handles render with unselected_char (e.g., `─`)
- `show_values=true` overlays low/high value strings adjacent to handles when space allows
- `focused_handle=.low` applies focused_style to low handle char; `.high` to high handle
- label rendered before track when non-empty

### v2.39.0 — NumberInput Widget (Released: 2026-06-13)

**Theme**: Numeric input control with min/max constraints, configurable step, decimal precision, label/prefix/suffix decoration, and focused state. Displays as `[Label] [-] <prefix><value><suffix> [+]` with keyboard-driven increment/decrement. Essential for TUI forms requiring bounded numeric input.

**Checklist**:
- [x] **src/tui/widgets/numberinput.zig** — NumberInput: init(); value/min/max/step (f64); decimal_places (u8); label/prefix/suffix strings; focused bool; increment()/decrement()/setValue(v) all clamped to [min,max]; isAtMin()/isAtMax() helpers; withMin/Max/Step/DecimalPlaces/Label/Prefix/Suffix/Value/Style/FocusedStyle/LabelStyle/Block builder API; render draws `[label] [-] <prefix><value><suffix> [+]`
- [x] **tests/numberinput_test.zig** — NumberInput tests (init defaults, increment/decrement clamping, setValue clamping, decimal display, builder immutability, render to Buffer, edge cases: zero area, narrow area, focused/unfocused, at-min/at-max states, negative values, large decimals) — 80 tests
- [x] Export NumberInput via tui.zig widgets struct
- [x] Add numberinput_tests to build.zig
- [x] Release v2.39.0

**Success Criteria**:
- `increment()` adds step to value, clamped to max; no-op at max
- `decrement()` subtracts step from value, clamped to min; no-op at min
- `setValue(v)` clamps v to [min, max]
- `isAtMin()` / `isAtMax()` return correct booleans
- `decimal_places=0` renders integer (no decimal point); decimal_places>0 renders fixed-point
- render draws `[-]` and `[+]` control markers around value
- focused state applies focused_style to value area
- label rendered before controls when non-empty
- Zero-area, narrow area handled without crash
- Negative min, negative values, step > range all handled correctly

**Notes**:
- No allocator — all strings are slices borrowed from caller
- Useful for: silica (query LIMIT/OFFSET), zoltraak (Redis TTL, keyspace count), zr (task priority/time estimate)

### v2.38.0 — KeyMap Widget (Released: 2026-06-13)

**Theme**: Keyboard shortcut reference panel displaying key bindings grouped into sections, with scroll navigation and optional two-column layout. Essential for any TUI application's help/cheatsheet overlay.

**Checklist**:
- [x] **src/tui/widgets/keymap.zig** — KeyMap: init(sections); KeyBinding (key, description); KeySection (title, bindings); scrollDown/scrollUp/pageDown/pageUp/goToTop/goToBottom navigation; totalRows() computes virtual rows; withBlock/withKeyStyle/withDescStyle/withSectionStyle/withColumns/withKeyWidth builder API; render draws section headers (bold) + binding rows (`<key>   <description>`) with scroll
- [x] **tests/keymap_test.zig** — KeyMap tests (init, navigation, builder immutability, render edge cases, 2-column layout, stress) — 85 tests
- [x] Export KeyMap, KeyBinding, KeySection via tui.zig widgets struct
- [x] Add keymap_tests to build.zig
- [x] Release v2.38.0

**Success Criteria**:
- scrollDown/scrollUp clamp scroll_offset within [0, max_scroll]
- pageDown/pageUp advance/retreat by visible_height rows
- goToTop/goToBottom set scroll_offset to extremes
- render draws section titles (bold/section_style) + binding rows (`<key><padding><description>`)
- columns=2 pairs consecutive bindings side by side in two equal columns
- withKeyWidth sets fixed width for key column (default 10)
- Zero-area, empty sections, single binding, narrow area handled without crash

**Notes**:
- No allocator needed — sections/bindings slices borrowed from caller
- Useful for: zr (task shortcuts), zoltraak (Redis command reference), silica (SQL help panel)
- Key column padding ensures alignment across all bindings in a section

### v2.37.0 — Pagination Widget (Released: 2026-06-13)

**Theme**: Horizontal page navigation control displaying `< 1 2 [3] 4 5 ... 10 >` style navigator. Useful for any TUI view that needs to paginate through results (SQL rows, Redis keys, task lists).

**Checklist**:
- [x] **src/tui/widgets/pagination.zig** — Pagination: init(total_pages); current_page/total_pages/max_visible_pages fields; nextPage/prevPage/goToPage/goToFirst/goToLast navigation (all clamped); withBlock/withStyle/withSelectedStyle/withArrowStyle/withMaxVisiblePages builder API; render draws `< 1 2 [N] 4 5 ... 10 >` with truncation ellipsis
- [x] **tests/pagination_test.zig** — Pagination tests (init, navigation, builder immutability, render edge cases, stress) — 90 tests
- [x] Export Pagination via tui.zig widgets struct
- [x] Add pagination_tests to build.zig
- [x] Release v2.37.0

**Success Criteria**:
- nextPage/prevPage clamp to [0, total_pages-1]
- goToPage(n) clamps to valid range; goToPage on 0-page count stays at 0
- goToFirst/goToLast set to extremes
- render draws page numbers in `< [current] >` style with brackets on current
- max_visible_pages truncation with `...` ellipsis for large page counts
- Zero-area, zero pages, single page handled without crash

**Notes**:
- No allocator needed — pure value type with stack-based rendering
- Useful for: silica (SQL result pages), zoltraak (Redis key pagination), zr (task list pages)

### v2.36.0 — FilterBar Widget (Released: 2026-06-12)

**Theme**: Multi-tag filter input bar for interactive data filtering — add/remove filter tags, preview active filters, support AND/OR logic. Useful for log filtering, search refinement, and data table filtering.

**Checklist**:
- [x] **src/tui/widgets/filter_bar.zig** — FilterBar: init(allocator); FilterTag (key, value, active: bool); addTag(key, value)/removeTag(index)/toggleTag(index)/clearAll(); activeCount(); withBlock/withTagStyle/withActiveStyle/withInactiveStyle/withPlaceholder builder API; render draws active tags as colored pills + inactive as dimmed, placeholder when empty
- [x] **tests/filter_bar_test.zig** — FilterBar tests (init, addTag, removeTag, toggleTag, clearAll, activeCount, render to Buffer, edge cases: empty, max tags, zero area, narrow area) — 77 tests
- [x] Export FilterBar, FilterTag via tui.zig widgets struct
- [x] Add filter_bar_tests to build.zig
- [x] Release v2.36.0

**Success Criteria**:
- addTag(key, value) appends new FilterTag (active=true by default)
- removeTag(index) removes tag at index (no-op if OOB)
- toggleTag(index) flips active state (no-op if OOB)
- clearAll() removes all tags
- activeCount() returns count of active tags only
- render draws tags as `[key:value]` pills, active in tag color, inactive dimmed
- Zero-area, empty tags, narrow area handled without crash

**Notes**:
- FilterBar needs allocator for dynamic tag list (like CommandBar)
- Useful for: silica (table column filters), zoltraak (Redis key pattern filters), zr (task label filters)

### v2.35.0 — LogViewer Widget (Released: 2026-06-12)

**Theme**: Scrollable log pane with log-level coloring, search/highlight, and tail mode. Useful for live log tailing, build output, and event streams.

**Checklist**:
- [x] **src/tui/widgets/logviewer.zig** — LogViewer: init(entries slice); LogEntry (timestamp_ms, level, message, source?); LogLevel enum (trace/debug/info/warn/err/fatal) with defaultColor(); scrollDown/scrollUp/pageDown/pageUp/goToTop/goToBottom navigation; search(query)/clearSearch(); tail_mode (auto-scroll to latest); withBlock/withLevelStyle/withSearchStyle/withShowLevels/withTailMode builder API; render draws [LEVEL] prefix tags with level color + message
- [x] **tests/log_viewer_test.zig** — LogViewer tests (init, navigation, search, tail mode, render to Buffer, edge cases: empty log, zero area, single entry, narrow area) — 77 tests
- [x] Export LogViewer, LogEntry, LogLevel via tui.zig widgets struct
- [x] Add log_viewer_tests to build.zig
- [x] Release v2.35.0

**Success Criteria**:
- scrollDown/scrollUp clamp scroll_offset within valid range
- search(query) highlights matching entries; clearSearch() resets
- tail_mode = true: scrolling to bottom on render (auto-follow new entries)
- render draws `[LEVEL]` prefix with level color, then entry text
- Zero-area, empty entries, single entry handled without crash

**Notes**:
- No allocator — entries slice borrowed from caller
- Useful for: zr (build/task output), zoltraak (Redis command log), silica (query history)

### v2.34.0 — StatusGrid Widget (Released: 2026-06-12)

**Theme**: Multi-cell status grid for monitoring dashboards — N×M cells each with label, value, and status color. Useful for cluster health, pipeline overview, and metric panels.

**Checklist**:
- [x] **src/tui/widgets/status_grid.zig** — StatusGrid: init with cells slice (rows×cols), StatusCell (label, value, status); StatusLevel enum (ok/warn/error_/unknown) with color(); cursor navigation (moveUp/Down/Left/Right, clamped); selectedCell(); withBlock/withCellStyle/withOkStyle/withWarnStyle/withErrorStyle/withUnknownStyle/withShowValues builder API; render draws labeled cells with status background color
- [x] **tests/status_grid_test.zig** — StatusGrid tests (init, navigation, selectedCell, status colors, render to Buffer, edge cases: empty cells, zero area, 1×1 grid, narrow area) — 70 tests
- [x] Export StatusGrid, StatusCell, StatusLevel via tui.zig widgets struct
- [x] Add status_grid_tests to build.zig
- [x] Release v2.34.0

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
- [x] **src/tui/widgets/inspector.zig** — Inspector: init with fields slice; InspectorField (key, value, field_type, depth); scrollUp/scrollDown/goToTop/goToBottom navigation; filterBy(query) hides non-matching fields; clearFilter(); withBlock/withKeyStyle/withValueStyle/withTypeStyle/withFilterStyle/withShowTypes/withShowFilter builder API; render draws key: value [type] rows with indentation for depth
- [x] **tests/inspector_test.zig** — Inspector tests (init, navigation, filter, clearFilter, render to Buffer, edge cases: empty fields, zero area, single field, deep nesting, narrow area) — 70 tests
- [x] Export Inspector, InspectorField via tui.zig widgets struct
- [x] Add inspector_tests to build.zig
- [x] Release v2.33.0

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
