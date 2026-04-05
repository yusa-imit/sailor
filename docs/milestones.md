# sailor — Milestones

## Current Status

- **Latest release**: v1.35.0 (2026-04-05) — Widget Accessibility & Keyboard Navigation
- **Latest minor**: v1.35.0 (2026-04-05) — Widget Accessibility & Keyboard Navigation
- **Next milestone**: v1.36.0 — Performance Monitoring & Real-Time Metrics
- **Active milestones**: 2
- **Blockers**: None

## Active Milestones

### v1.36.0 — Performance Monitoring & Real-Time Metrics
**Theme**: Built-in performance monitoring and widget-level metrics
**Target**: 2026-04 (1-2 weeks)
**Rationale**: Establish baseline metrics before v2.0.0 breaking changes; help consumer projects optimize their UIs
**Checklist**:
- [x] Widget render metrics - measure render time per widget (min/max/avg, percentiles) (Session 71: render_metrics.zig, +31 tests)
- [ ] Memory usage tracking - track allocation patterns per widget (peak memory, allocation count)
- [ ] Event processing metrics - measure event handling latency (input lag, event queue depth)
- [ ] Live metrics dashboard widget - real-time visualization of performance data
- [ ] Performance regression tests - automated tests to detect performance degradation
- [ ] Example: metrics_dashboard.zig - demonstrate performance monitoring

### v1.37.0 — v2.0.0 Deprecation Warnings & Bridge APIs
**Theme**: Introduce v2.0.0 APIs alongside v1.x APIs with deprecation warnings
**Target**: 2026-04 (1-2 weeks)
**Rationale**: Enable gradual migration to v2.0.0 APIs; provide clear deprecation warnings
**Checklist**:
- [ ] Deprecation warning system - compile-time warnings for deprecated APIs
- [ ] Buffer.set() alongside setChar() - introduce v2.0.0 naming convention
- [ ] Style inference helpers - simplify color specification (.red instead of Color{ .basic = .red })
- [ ] Widget lifecycle standardization - consistent init/deinit patterns across all widgets
- [ ] Migration guide document - docs/v1-to-v2-migration.md with examples
- [ ] Example: migration_demo.zig - side-by-side v1.x vs v2.0.0 APIs

### v1.33.0 — Specialized Widgets & Components
**Theme**: Expand widget library with specialized components for common use cases
**Target**: 2026-04 (1-2 weeks)
**Rationale**: Consumer projects need domain-specific widgets (logs, metrics, config panels)
**Checklist**:
- [x] LogViewer widget - scrollable log display with filtering and search (pre-existing from v1.8.0)
- [x] MetricsPanel widget - real-time metrics display with thresholds (Session 62: +34 tests, gauge/counter/rate types, 3 layout modes, sparklines)
- [x] ConfigEditor widget - hierarchical config editing (JSON/TOML) (Session 62: +45 tests, tree view, 6 value types, expand/collapse)
- [x] SplitPane widget - resizable panes with drag handles (Session 62: +36 tests, h/v splits, min/max constraints, visual divider)
- [x] Breadcrumb widget - navigation breadcrumb trail (Session 63: +51 tests, 3 truncation modes, custom separators, highlighting)
- [x] Tooltip widget - contextual help tooltips (Session 64: +53 tests, 5 positioning strategies, arrow indicators, boundary detection)

### v1.34.0 — Terminal Clipboard & System Integration
**Theme**: Enhance terminal integration with system clipboard and OS features
**Target**: 2026-04 (1-2 weeks)
**Rationale**: Widget copy/paste workflows need clipboard access; terminal emulator feature detection improves UX
**Checklist**:
- [x] Clipboard API - read/write system clipboard via OSC 52 escape sequences (Session 65: clipboard.zig, +30 tests)
- [x] Terminal emulator detection - identify terminal type (xterm, kitty, iTerm2, Windows Terminal) (Session 66: terminal_detect.zig, +22 tests)
- [x] Feature capability query - runtime detection of terminal features (truecolor, mouse, clipboard) (Session 66: terminal_caps.zig, +37 tests)
- [x] Paste bracketing enhancements - improved multi-line paste handling (Session 67: paste.zig, +38 tests, PasteHandler/PasteReader)
- [ ] Clipboard widget mixin - add copy/paste to any widget (DEFERRED: OSC 52 read not widely supported by terminals)
- [x] Example: clipboard_demo.zig - demonstrate clipboard operations (Session 67: comprehensive demo with all features)

### v1.28.0 — Ecosystem Integration & Polish (COMPLETED 2026-04-01)
**Theme**: zuda integration, consumer feedback, final polish
**Checklist**:
- [x] Audit for zuda-compatible algorithms (sorting, searching, hashing) — docs/zuda-audit.md
- [x] Replace custom implementations with zuda imports where applicable — N/A (no replacements needed)
- [x] Address any open consumer issues (from:zr, from:zoltraak, from:silica) — 0 open issues
- [x] Performance benchmarking across all widgets — docs/benchmark-report.md (12 widgets, all <0.02ms/op)
- [x] Release v2.0.0 planning document — docs/v2.0.0-planning.md (DRAFT RFC)

### v1.22.0 — Rich Text & Formatting (COMPLETED 2026-03-26)
**Theme**: Advanced text rendering and inline formatting
**Checklist**:
- [x] Inline styles - SpanBuilder/LineBuilder fluent APIs (56 tests)
- [x] Rich text parser - markdown-to-spans conversion (45 tests)
- [x] Text alignment - left/center/right/justify (already in Paragraph)
- [x] Line breaking - word wrap with hyphenation support (31 tests)
- [x] Text measurements - Unicode-aware dimension calculation (47 tests)

### v1.24.0 — Animation & Transitions (COMPLETE)
**Theme**: Smooth transitions, effects, and time-based rendering
**Target**: 2026-04 (1-2 weeks)
**Checklist**:
- [x] Animation trait - define keyframe/tween protocol
- [x] Transition helpers - fade, slide, expand/collapse
- [x] Timer system - async animation scheduling (30 tests, Session 22)
- [x] Easing functions - smooth interpolation (22 total: linear, cubic, elastic, bounce, back, circ, expo)
- [x] Example animations - animation_demo.zig showcasing all features

### v1.23.0 — Plugin Architecture & Extensibility (COMPLETED 2026-03-27)
**Theme**: Enable custom widgets and renderer extensions
**Checklist**:
- [x] Widget trait system - define renderable/focusable/eventable traits (already complete in widget_trait.zig)
- [x] Custom renderer hooks - allow pre/post render callbacks (15 tests, Terminal.draw())
- [x] Theme plugin system - load themes from external files (JSON) — 25 tests (Session 17)
- [x] Widget composition helpers - decorators, wrappers, containers — 26 tests (Session 18)
- [x] Example plugin - demonstrate third-party widget integration (plugin_demo.zig + 10 tests)

## Completed Milestones

| Version | Name | Date | Summary |
|---------|------|------|---------|
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
