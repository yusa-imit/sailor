# sailor — Milestones

## Current Status

- **Latest release**: v2.4.0 (2026-04-29) — Testing Infrastructure & Quality Tooling
- **Latest minor**: v2.4.0 (2026-04-29) — Snapshot testing, property-based testing, visual regression, mock terminal, test utilities
- **Next milestone**: v2.5.0 (iTerm2 Protocol & Unicode Grapheme Support)
- **Active milestones**: 2 (v2.2.0, v2.5.0)
- **Blockers**: None

## Active Milestones

### v2.5.0 — iTerm2 Protocol & Unicode Grapheme Support (Target: 2026-05-05)

**Theme**: Advanced terminal protocols and proper Unicode handling for modern terminals

**Checklist**:
- [x] **iTerm2 inline images protocol**: OSC 1337 image rendering
  - File transfer syntax (File=inline=1;[base64])
  - Positioning and sizing (width, height, preserveAspectRatio)
  - Terminal capability detection (iTerm2, WezTerm support)
  - Image cache management (memory limits, eviction)
  - Error handling for unsupported terminals
- [x] **Unicode grapheme cluster support**: Proper multi-codepoint character handling
  - Grapheme boundary detection (UAX#29 rules)
  - Display width calculation for grapheme clusters (emoji, combining marks, ZWJ sequences)
  - Cursor positioning with grapheme awareness
  - Text wrapping respects grapheme boundaries
  - Buffer Cell storage for grapheme clusters (existing Cell structure + grapheme-aware helpers)
- [ ] **Terminal quirks database**: Handle emulator-specific behaviors
  - Known issues database (per-terminal workarounds)
  - Auto-detection of terminal bugs (response parsing)
  - Graceful fallbacks for broken terminals
  - Quirk flags (disable problematic features)
- [ ] **Performance benchmarks**: Real-world scenario benchmarks
  - Widget composition overhead (nested layouts)
  - Large dataset rendering (10K+ rows)
  - Event loop latency (input-to-render)
  - Memory allocation patterns
  - Regression detection in CI
- [ ] **Testing**: Comprehensive test coverage for all features
  - iTerm2 protocol encoding/decoding tests
  - Grapheme cluster test suite (emoji, combining marks, ligatures)
  - Quirks database tests (mock terminal responses)
  - Benchmark stability tests (variance < 5%)

**Success Criteria**:
- iTerm2 users can render inline images seamlessly
- Emoji and complex Unicode render correctly (no broken cursor positioning)
- All tests passing (~3800+ tests expected)
- Benchmarks show <0.02ms/op for widget operations
- Documentation includes grapheme handling guide

**Notes**:
- iTerm2 protocol complements Kitty/Sixel for broader terminal support
- Grapheme support fixes long-standing emoji/combining mark issues
- Quirks database improves robustness across terminal emulators
- Performance benchmarks establish baseline for future optimizations

### v2.2.0 — Consumer Feedback & Bug Fixes (Target: 2026-05-15)

**Theme**: Address real-world usage feedback from zr, zoltraak, silica migrations

**Checklist**:
- [ ] **Monitor consumer migrations**: Track progress of v2.1.0 migrations
  - zr#54, zoltraak#31, silica#40
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
- All consumer projects successfully migrated to v2.1.0
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
