# sailor — Milestones

## Current Status

- **Latest release**: v1.18.0 (2026-03-21) — Developer Experience & Tooling
- **Latest minor**: v1.18.0 (2026-03-21) — Developer Experience & Tooling
- **Next milestone**: TBD (need to establish new milestone)
- **Blockers**: None

## Active Milestones

### v1.19.0 — CLI Enhancements & Ergonomics

**Theme**: Improve core CLI modules for better developer experience in consumer projects

**Scope**:
- [ ] Enhanced arg parser with positional arguments and argument groups
- [ ] Color themes & color scheme management (light/dark mode auto-switching)
- [ ] Table formatting improvements (alignment, padding control, multi-line cells)
- [ ] Progress bar templates and presets (spinners, styles, formats)
- [ ] Environment variable configuration support across all modules

**Rationale**: Consumer projects (zr, zoltraak, silica) heavily use arg, color, fmt, progress. Enhancing these foundational modules provides immediate value to all users.

**Dependencies**: None (all modules already exist)

**Target completion**: 1-2 weeks

## Completed Milestones

| Version | Name | Date | Summary |
|---------|------|------|---------|
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
