# sailor — Claude Code Orchestrator

> **sailor**: Zig TUI framework & CLI toolkit
> Current Phase: **Phase 6 — Polish**

---

## Project Overview

- **Language**: Zig 0.15.x
- **Type**: Library (consumed via `build.zig.zon`)
- **Build**: `zig build` / `zig build test`
- **PRD**: `docs/PRD.md` (전체 요구사항 참조)
- **Branch Strategy**: `main` (development)

## Repository Structure

```
sailor/
├── CLAUDE.md                    # THIS FILE — orchestrator
├── docs/PRD.md                  # Product Requirements Document
├── .gitignore                   # Git ignore rules
├── .claude/
│   ├── agents/                  # Custom subagent definitions
│   │   ├── zig-developer.md     #   model: sonnet — Zig 구현
│   │   ├── code-reviewer.md     #   model: sonnet — 코드 리뷰
│   │   ├── test-writer.md       #   model: sonnet — 테스트 작성
│   │   ├── architect.md         #   model: opus   — 아키텍처 설계
│   │   ├── git-manager.md       #   model: haiku  — Git 운영
│   │   └── ci-cd.md             #   model: haiku  — CI/CD 관리
│   ├── commands/                # Slash commands
│   ├── memory/                  # Persistent agent memory
│   └── settings.json            # Claude Code permissions
├── .github/workflows/           # CI/CD pipelines
│   └── ci.yml                   #   Build, test, cross-compile
├── src/                         # Library source
│   ├── sailor.zig               #   Root module — pub exports
│   ├── term.zig                 #   Terminal backend
│   ├── color.zig                #   Styled output
│   ├── arg.zig                  #   Argument parser
│   ├── repl.zig                 #   Interactive REPL
│   ├── progress.zig             #   Progress indicators
│   ├── fmt.zig                  #   Result formatting
│   └── tui/                     #   TUI framework
│       ├── tui.zig              #     Terminal, Frame, event loop
│       ├── buffer.zig           #     Cell buffer, diff engine
│       ├── layout.zig           #     Constraint solver
│       ├── style.zig            #     Style, Color, Span, Line
│       ├── symbols.zig          #     Box-drawing character sets
│       └── widgets/             #     Built-in widgets
│           ├── block.zig
│           ├── paragraph.zig
│           ├── list.zig
│           ├── table.zig
│           ├── tree.zig
│           ├── input.zig
│           ├── textarea.zig
│           ├── tabs.zig
│           ├── gauge.zig
│           ├── sparkline.zig
│           ├── barchart.zig
│           ├── linechart.zig
│           ├── canvas.zig
│           ├── dialog.zig
│           ├── notification.zig
│           ├── popup.zig
│           └── statusbar.zig
├── tests/                       # Tests
│   ├── term_test.zig
│   ├── color_test.zig
│   ├── arg_test.zig
│   ├── repl_test.zig
│   ├── progress_test.zig
│   ├── fmt_test.zig
│   ├── buffer_test.zig
│   ├── layout_test.zig
│   └── widget_test.zig
└── examples/                    # Example applications
    ├── hello.zig                #   Minimal TUI app
    ├── counter.zig              #   Interactive counter
    └── dashboard.zig            #   Multi-widget dashboard
```

---

## Development Workflow

### Autonomous Development Protocol

Claude Code는 이 프로젝트에서 **완전 자율 개발**을 수행한다. 다음 프로토콜을 따른다:

1. **작업 수신** → PRD 또는 사용자 지시를 분석
2. **계획 수립** → 대화형 세션: `EnterPlanMode`로 사용자 승인; 자율 세션(`claude -p`): 내부적으로 계획 후 즉시 구현 진행 (plan mode 도구 사용 금지)
3. **팀 구성** → 작업 복잡도에 따라 동적으로 팀/서브에이전트 생성
4. **구현** → 코딩, 테스트, 리뷰를 병렬 수행
5. **검증** → `zig build test`로 전체 테스트 통과 확인
6. **커밋** → 변경사항 커밋 (사용자 요청 시)
7. **메모리 갱신** → `.claude/memory/`에 기록

### Team Orchestration

복잡한 작업 시 다음 패턴으로 팀을 구성한다:

```
Leader (orchestrator)
├── zig-developer   — 구현 담당
├── code-reviewer   — 코드 리뷰 & 품질 보증
├── test-writer     — 테스트 작성
└── architect       — 설계 검토 (필요 시)
```

**팀 생성 기준**:
- 3개 이상 파일 수정이 필요한 작업 → 팀 구성
- 단일 파일 수정 → 직접 수행
- 아키텍처 변경 → architect 포함

**팀 해산**: 작업 완료 후 반드시 `shutdown_request` → `TeamDelete`로 정리

### Automated Session Execution

자동화 세션(cron job 등)에서는 다음 프로토콜을 순서대로 실행한다.

**컨텍스트 복원** — 세션 시작 시 다음 파일을 읽어 프로젝트 상태 파악:
1. `.claude/memory/project-context.md` — 현재 phase, 체크리스트, 진행 상황
2. `.claude/memory/architecture.md` — 아키텍처 결정사항
3. `.claude/memory/decisions.md` — 기술 결정 로그
4. `.claude/memory/debugging.md` — 알려진 이슈와 해결법
5. `.claude/memory/patterns.md` — 검증된 코드 패턴

**9단계 실행 사이클**:

| Phase | 내용 | 비고 |
|-------|------|------|
| 1. 상태 파악 | `/status` 실행, git log·빌드·테스트 상태 점검 | 체크리스트에서 다음 미완료 항목 식별 |
| 1.5. 이슈 확인 | `gh issue list --state open --limit 10` | 아래 **이슈 우선순위 프로토콜** 참조 |
| 2. 계획 | 구현 전략을 내부적으로 수립 (텍스트 출력) | `EnterPlanMode`/`ExitPlanMode` 사용 금지 — 비대화형 세션에서 블로킹됨 |
| 3. 구현 → 검증 → 커밋 (반복) | 아래 **구현 루프** 참조 | 단위별로 즉시 커밋+푸시 |
| 4. 코드 리뷰 | `/review` — PRD 준수·메모리 안전성·테스트 커버리지 확인 | 이슈 발견 시 수정 후 재커밋 |
| 5. 릴리즈 판단 | 현재 phase의 모든 모듈 완료 시 **자동 릴리즈** | 아래 **자동 릴리즈 프로토콜** 참조 |
| 6. 메모리 갱신 | `.claude/memory/` 파일 업데이트 | 별도 커밋: `chore: update session memory` → push |
| 7. 세션 요약 | 구조화된 요약 출력 | 아래 템플릿 참조 |

**구현 루프** (Phase 3 상세):

작업을 작은 단위로 분할하고, 각 단위마다 다음을 반복한다:
1. 코드 작성 (하나의 모듈/파일 단위)
2. 테스트 작성 및 `zig build test` 통과 확인
3. 즉시 커밋 + `git push` — 다음 단위로 넘어가기 전에 반드시 수행
- 미커밋 변경사항을 여러 파일에 걸쳐 누적하지 않는다
- 한 사이클 내에 완료할 수 없는 작업은 동작하는 중간 상태로 커밋+푸시한다
- `git add -A` 금지 — 변경된 파일을 명시적으로 지정

**이슈 우선순위 프로토콜** (Phase 1.5):

세션 시작 시 GitHub Issues를 확인하고, PRD 기능과 비교하여 우선순위를 결정한다:

```bash
gh issue list --state open --limit 10 --json number,title,labels,createdAt
```

**우선순위 판단 기준**:

| 우선순위 | 조건 | 예시 |
|---------|------|------|
| 1 (최우선) | `bug` 라벨 + consumer 프로젝트에서 발행 | sailor 사용 중 크래시, API 오동작 |
| 2 (높음) | `bug` 라벨 (일반) | 테스트 실패, 빌드 오류 |
| 3 (보통) | `feature-request` 라벨 + 현재 phase 범위 내 | 현재 구현 중인 모듈의 추가 기능 |
| 4 (낮음) | `feature-request` 라벨 + 미래 phase | 아직 구현 안 된 모듈의 기능 요청 |

**판단 규칙**:
- 우선순위 1-2 (버그): PRD 기능보다 **항상 우선** 처리
- 우선순위 3 (현재 phase 기능 요청): PRD 작업과 **병행** — 같은 모듈 작업 시 함께 구현
- 우선순위 4 (미래 phase 기능 요청): **적어두고 넘어감** — 해당 phase 도달 시 처리
- 이슈를 처리한 후: `gh issue close <number> --comment "Fixed in <commit-hash>"`
- 이슈에 코멘트로 진행 상황 공유: `gh issue comment <number> --body "Working on this in current session"`

**자동 릴리즈 프로토콜** (Phase 5):

phase의 모든 모듈이 완성되었을 때 에이전트가 자율적으로 릴리즈를 수행한다.

**릴리즈 조건 (ALL must be true)**:
1. 현재 phase의 체크리스트 항목이 **모두 완료** (`[x]`)
2. `zig build test` — 전체 통과, 0 failures
3. 6개 크로스 컴파일 타겟 빌드 성공
4. 해당 phase 관련 `bug` 라벨 이슈가 **0개** (open)

**릴리즈 절차**:
1. `build.zig.zon`의 version 업데이트 (예: `"0.0.0"` → `"0.1.0"`)
2. CLAUDE.md phase 체크리스트에 완료 표시
3. 커밋: `chore: bump version to v0.X.0`
4. 태그: `git tag -a v0.X.0 -m "Release v0.X.0: <phase 요약>"`
5. 푸시: `git push && git push origin v0.X.0`
6. GitHub Release 생성: `gh release create v0.X.0 --title "v0.X.0: <phase 요약>" --notes "<릴리즈 노트>"`
7. 소비자 프로젝트 알림 — 각 프로젝트의 CLAUDE.md에서 해당 버전 `status: PENDING` → `status: READY`:
   - `../zr/CLAUDE.md`
   - `../zoltraak/CLAUDE.md`
   - `../silica/CLAUDE.md`
   - 각각 커밋: `chore: mark sailor v0.X.0 migration as ready`
8. 관련 이슈 닫기: `gh issue close <number> --comment "Resolved in v0.X.0"`
9. Discord 알림: `openclaw message send --channel discord --target user:264745080709971968 --message "[sailor] Released v0.X.0 — <요약>"`

**패치 릴리즈 정책** (v0.X.Y):

소비자 프로젝트(`from:*` 라벨) 버그 수정 시 패치 릴리즈를 즉시 발행한다.

**트리거 조건**:
- `from:*` 라벨 버그가 수정된 커밋이 존재하지만 릴리즈 태그가 없을 때
- 빌드/테스트 실패를 수정한 커밋
- 크로스 컴파일 깨짐을 수정한 커밋

**패치 vs 마이너 판단**:
- 버그 수정만 포함 → PATCH (v0.X.Y)
- 새 기능 포함 → MINOR (v0.X+1.0)

**버전 규칙**:
- PATCH 번호만 증가 (예: v0.5.0 → v0.5.1)
- `build.zig.zon` version 수정 불필요 — 태그만으로 충분
- 기능 커밋을 패치에 포함하지 않음

**패치 릴리즈 절차**:
1. 버그 수정 커밋 식별 (예: `357fa25`)
2. `zig build test` 통과 확인
3. 태그: `git tag -a v0.X.Y <commit-hash> -m "Release v0.X.Y: <수정 요약>"`
4. 푸시: `git push origin v0.X.Y`
5. GitHub Release: `gh release create v0.X.Y --title "v0.X.Y: <요약>" --notes "<릴리즈 노트>"`
6. 관련 이슈에 릴리즈 코멘트 추가
7. 소비자 프로젝트 CLAUDE.md에 패치 안내 추가
8. Discord 알림

**작업 선택 규칙**:
- `build.zig`가 없으면 프로젝트 부트스트랩부터 시작
- 이전 세션의 미커밋 변경사항이 있으면: 테스트 통과 시 커밋+푸시, 실패 시 폐기
- 테스트 실패 중이면 새 기능 추가 전에 수정
- 의존성 순서 준수: term → color → arg → repl → progress → fmt → tui
- 사이클당 하나의 집중 작업만 수행
- 이전 세션의 미완료 작업이 있으면 먼저 완료
- **GitHub 이슈 bug 라벨은 PRD 작업보다 항상 우선**

**세션 요약 템플릿**:

    ## Session Summary
    ### Completed
    - [이번 사이클에서 완료한 내용]
    ### Files Changed
    - [생성/수정된 파일 목록]
    ### Tests
    - [테스트 수, 통과/실패 상태]
    ### Next Priority
    - [다음 사이클에서 작업할 내용]
    ### Issues / Blockers
    - [발생한 문제 또는 미해결 이슈]

### Consumer Projects

sailor는 세 프로젝트의 공유 라이브러리다:

| Project | Path | Uses |
|---------|------|------|
| **zr** | `../zr` | arg, color, progress → 후에 tui 마이그레이션 |
| **zoltraak** | `../zoltraak` | arg, color, repl → 후에 tui (redis-cli) |
| **silica** | `../silica` | arg, color, repl, fmt → 후에 tui (SQL shell) |

API 변경 시 소비자 프로젝트 호환성을 반드시 고려한다.

### Available Custom Agents

| Agent | Model | File | Purpose |
|-------|-------|------|---------|
| zig-developer | sonnet | `.claude/agents/zig-developer.md` | Zig 코드 구현, 빌드 오류 해결 |
| code-reviewer | sonnet | `.claude/agents/code-reviewer.md` | 코드 리뷰, 품질/보안 검사 |
| test-writer | sonnet | `.claude/agents/test-writer.md` | 유닛 테스트 작성 |
| architect | opus | `.claude/agents/architect.md` | 아키텍처 설계, 모듈 구조 결정 |
| git-manager | haiku | `.claude/agents/git-manager.md` | Git 운영, 브랜치/커밋 관리 |
| ci-cd | haiku | `.claude/agents/ci-cd.md` | GitHub Actions, CI/CD 파이프라인 |

### Available Slash Commands

| Command | File | Purpose |
|---------|------|---------|
| /build | `.claude/commands/build.md` | 라이브러리 빌드 |
| /test | `.claude/commands/test.md` | 테스트 실행 |
| /review | `.claude/commands/review.md` | 현재 변경사항 코드 리뷰 |
| /implement | `.claude/commands/implement.md` | 기능 구현 워크플로우 |
| /fix | `.claude/commands/fix.md` | 버그 수정 워크플로우 |
| /status | `.claude/commands/status.md` | 프로젝트 상태 확인 |
| /release | `.claude/commands/release.md` | 릴리스 워크플로우 |
| /example | `.claude/commands/example.md` | 예제 앱 빌드 및 실행 |

---

## Coding Standards

### Zig Conventions

- **Naming**: camelCase for functions/variables, PascalCase for types, SCREAMING_SNAKE for constants
- **Error handling**: Always use explicit error unions, never `catch unreachable` in library code
- **Memory**: Prefer arena allocators for request-scoped work, GPA for long-lived allocations. Library functions accept `std.mem.Allocator` — never hardcode allocator.
- **Testing**: Every public function must have corresponding tests in the same file
- **Comments**: Only where logic is non-obvious. No doc comments on self-explanatory functions
- **Imports**: Group stdlib, then project imports, then test imports

### Library-Specific Rules

- **No global state** — All state in structs, caller owns lifetime
- **No stdout/stderr** — Write to user-provided `std.io.Writer` only
- **No `@panic` in library code** — Return errors, let caller decide
- **No `std.debug.print`** — Use proper writer-based output
- **Comptime validation** — Validate API misuse at compile time where possible
- **Backward compatibility** — API changes require deprecation cycle across consumer projects

### File Organization

- One module per file
- Keep files under 500 lines; split into submodules if exceeded
- Public API at top of file, private helpers at bottom
- Tests at the bottom of each file within `test` block
- Widget files follow pattern: struct definition → render fn → helper fns → tests

### Error Messages

Library errors should be descriptive:
```zig
error.InvalidConstraint  // not error.Invalid
error.TerminalNotATty    // not error.NotTty
error.UnknownFlag        // not error.Unknown
```

---

## Git Workflow

### Branch Strategy

- `main` — primary development branch
- Feature branches: `feat/<name>`, `fix/<name>`, `refactor/<name>`

### Commit Convention

```
<type>: <subject>

<body>

Co-Authored-By: Claude <noreply@anthropic.com>
```

Types: `feat`, `fix`, `refactor`, `test`, `chore`, `docs`, `perf`, `ci`

---

## Memory System

### Long-Term Memory Preservation

에이전트와 오케스트레이터는 `.claude/memory/` 디렉토리에 장기 기억을 보존한다.

**메모리 파일 구조**:
```
.claude/memory/
├── project-context.md    # 프로젝트 개요, 현재 phase, 체크리스트
├── architecture.md       # 아키텍처 결정사항
├── decisions.md          # 주요 기술 결정 로그
├── debugging.md          # 디버깅 인사이트, 해결된 문제
└── patterns.md           # 검증된 코드 패턴
```

**메모리 프로토콜**:
1. 세션 시작 시 `.claude/memory/` 파일들을 읽어 컨텍스트 복원
2. 중요한 결정/발견 시 즉시 해당 메모리 파일에 기록
3. 메모리 파일이 200줄을 초과하면 핵심만 남기고 압축

---

## Phase Implementation Roadmap

### Phase 1 — Terminal + CLI Foundation (v0.1.0) ✅ RELEASED
- [x] `src/term.zig` — Raw mode, key reading, TTY detection, terminal size
- [x] `src/color.zig` — ANSI codes, styles, 256/truecolor, NO_COLOR
- [x] `src/arg.zig` — Flag parsing, subcommands, help generation
- [x] Tests for all Phase 1 modules (102/102 passing)
- [x] CI pipeline passing

### Phase 2 — Interactive (v0.2.0) ✅ RELEASED
- [x] `src/repl.zig` — Line editing, history, completion, highlighting
- [x] `src/progress.zig` — Bar, spinner, multi-progress
- [x] `src/fmt.zig` — Table, JSON, CSV, plain output
- [x] Tests for all Phase 2 modules

### Phase 3 — TUI Core (v0.3.0) ✅ COMPLETE
- [x] `src/tui/style.zig` — Style, Color, Span, Line
- [x] `src/tui/symbols.zig` — Box-drawing sets
- [x] `src/tui/layout.zig` — Constraint solver
- [x] `src/tui/buffer.zig` — Cell grid, double buffering, diff
- [x] `src/tui/tui.zig` — Terminal wrapper, Frame, event loop
- [x] Tests for TUI core (96 tests passing)

### Phase 4 — Core Widgets (v0.4.0) ✅ COMPLETE
- [x] Block, Paragraph, List, Table, Input, Tabs, StatusBar, Gauge
- [x] All 8 core widgets implemented with comprehensive tests
- [ ] Consumer migration: zr, zoltraak-cli, silica shell prototypes (next phase)

### Phase 5 — Advanced Widgets (v0.5.0) ✅ RELEASED
- [x] Tree, TextArea, Sparkline, BarChart, LineChart
- [x] Canvas, Dialog, Popup, Notification
- [x] v0.5.1 patch: fix 4 consumer project bugs (#3, #4, #5, #6)

### Phase 6 — Polish (v1.0.0)
- [x] Theming system
- [x] Animation support
- [x] Performance benchmarks
- [x] Example applications (hello, counter, dashboard)
- [ ] Comprehensive documentation

---

## Quick Reference

```bash
# Build library
zig build

# Test
zig build test

# Build and run example
zig build example -- hello

# Cross-compile check
zig build -Dtarget=x86_64-linux-gnu

# Clean
rm -rf zig-out .zig-cache
```

---

## Rules for Claude Code

1. **Always read before writing** — 파일 수정 전 반드시 Read로 현재 내용 확인
2. **Test after every change** — 코드 변경 후 `zig build test` 실행
3. **Incremental commits** — 기능 단위로 작은 커밋
4. **Memory updates** — 중요한 발견/결정은 즉시 메모리에 기록
5. **No over-engineering** — 현재 phase에 필요한 것만 구현
6. **PRD is source of truth** — 기능 요구사항은 `docs/PRD.md` 참조
7. **Team cleanup** — 팀 작업 완료 후 반드시 해산
8. **Library mindset** — stdout 직접 사용 금지, Writer 기반 API만 제공
9. **Consumer awareness** — API 변경 시 zr, zoltraak, silica 호환성 고려
10. **Stop if stuck** — 동일 에러 3회 시도 후 지속되면 `.claude/memory/debugging.md`에 기록
11. **Respect CI** — CI 파이프라인 호환성 유지
12. **Never force push** — 파괴적 git 명령어 금지

---

## Release & Consumer Migration Protocol

sailor는 세 프로젝트(zr, zoltraak, silica)의 공유 라이브러리다. 버전 릴리즈 시 소비자 프로젝트에 마이그레이션을 알려야 한다.

### 릴리즈 시 필수 절차

새 버전 태그 후, 각 소비자 프로젝트의 CLAUDE.md에서 `## Sailor Migration` 섹션의 해당 버전 체크리스트를 `READY`로 업데이트한다:

```bash
# 1. sailor 릴리즈 완료 후
cd ../zr
# CLAUDE.md의 sailor migration 섹션에서 해당 버전의 status를 READY로 변경

cd ../zoltraak
# 동일하게 CLAUDE.md 업데이트

cd ../silica
# 동일하게 CLAUDE.md 업데이트
```

### 업데이트 규칙

1. 각 소비자 프로젝트의 `CLAUDE.md` → `## Sailor Migration` 섹션을 찾는다
2. 릴리즈된 버전의 `status: PENDING` → `status: READY`로 변경한다
3. 변경사항을 커밋한다: `chore: mark sailor <version> migration as ready`
4. **코드 마이그레이션은 하지 않는다** — 소비자 프로젝트의 에이전트가 자체적으로 수행

### 버전별 소비자 마이그레이션 매핑

| sailor 버전 | zr | zoltraak | silica |
|------------|-----|----------|--------|
| v0.1.0 | arg, color 마이그레이션 | `parseArgs()` → `sailor.arg`, 서버 로그 color | CLI 플래그 추가 |
| v0.2.0 | progress 마이그레이션 | REPL 빌드 (`zoltraak-cli`) | SQL 셸 스켈레톤 |
| v0.3.0 | JSON output → sailor.fmt | 결과 포매팅 | `.mode table/csv/json` |
| v0.4.0 | TUI 마이그레이션 (태스크 피커, 라이브 러너) | 키 브라우저, 데이터 뷰어 | 스키마 브라우저, 결과 테이블 |
| v0.5.0 | 의존성 트리, 차트 | 모니터링 대시보드 | 쿼리 플랜 시각화 |
