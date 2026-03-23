# sailor — Claude Code Orchestrator

> **sailor**: Zig TUI framework & CLI toolkit
> All phases complete (v1.0.0+). Post-release development via milestones.

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
├── CLAUDE.md / docs/PRD.md      # Orchestrator / Requirements
├── .claude/                     # Agents, commands, memory, settings
├── .github/workflows/ci.yml     # CI/CD pipeline
├── src/
│   ├── sailor.zig               # Root module — pub exports
│   ├── term.zig / color.zig / arg.zig / repl.zig / progress.zig / fmt.zig
│   └── tui/                     # TUI framework (tui, buffer, layout, style, symbols, 17 widgets)
├── tests/                       # Module tests (*_test.zig)
└── examples/                    # hello, counter, dashboard
```

> **Note**: 파일 구조는 참고안. 소스 코드가 기준.

---

## Development Workflow

### Autonomous Development Protocol

Claude Code는 이 프로젝트에서 **완전 자율 개발**을 수행한다. 다음 프로토콜을 따른다:

1. **작업 수신** → PRD 또는 사용자 지시를 분석
2. **계획 수립** → 대화형 세션: `EnterPlanMode`로 사용자 승인; 자율 세션(`claude -p`): 내부적으로 계획 후 즉시 구현 진행 (plan mode 도구 사용 금지)
3. **팀 구성** → 작업 복잡도에 따라 동적으로 팀/서브에이전트 생성
4. **구현** → TDD 사이클: 테스트 작성(test-writer) → 구현(zig-developer) → 리뷰 순차 수행
5. **검증** → `zig build test`로 전체 테스트 통과 확인
6. **커밋** → 변경사항 커밋 (사용자 요청 시)
7. **메모리 갱신** → `.claude/memory/`에 기록

### Team Orchestration

복잡한 작업 시 다음 패턴으로 팀을 구성한다:

```
Leader (orchestrator)
├── test-writer     — 테스트 먼저 작성 (MUST run before zig-developer)
├── zig-developer   — 테스트를 통과시키는 구현
├── code-reviewer   — 코드 리뷰 & 품질 보증
└── architect       — 설계 검토 (필요 시)
```

**TDD 실행 규칙**:
- `test-writer`는 모든 구현 작업에서 필수로 먼저 호출한다 (단일 파일 수정 포함)
- `zig-developer`는 `test-writer`가 작성한 실패하는 테스트가 존재한 후에만 호출한다
- 테스트 수정이 필요하면 `zig-developer`가 직접 수정하지 않고 `test-writer`를 재호출한다
- 테스트는 커버리지 수치가 아닌 의미 있는 검증을 기준으로 작성한다

**팀 생성 기준**:
- 3개 이상 파일 수정 → 팀 구성 (test-writer 필수 포함)
- 단일 파일 수정 → test-writer 서브에이전트 호출 후 직접 구현
- 아키텍처 변경 → architect + test-writer 포함

**팀 해산**: 작업 완료 후 반드시 `shutdown_request` → `TeamDelete`로 정리

### Automated Session Execution

자동화 세션(cron job 등)에서는 다음 프로토콜을 순서대로 실행한다.

**컨텍스트 복원** — 세션 시작 시 다음 파일을 읽어 프로젝트 상태 파악:
1. `.claude/memory/project-context.md` — 현재 phase, 체크리스트, 진행 상황
2. `.claude/memory/architecture.md` — 아키텍처 결정사항
3. `.claude/memory/decisions.md` — 기술 결정 로그
4. `.claude/memory/debugging.md` — 알려진 이슈와 해결법
5. `.claude/memory/patterns.md` — 검증된 코드 패턴
6. `docs/milestones.md` — 마일스톤 로드맵, 의존성 추적

**9단계 실행 사이클**:

| Phase | 내용 | 비고 |
|-------|------|------|
| 1. 상태 파악 | `/status` 실행, git log·빌드·테스트 상태 점검 | `docs/milestones.md`에서 다음 미완료 항목 식별 |
| 1.5. 이슈 확인 | `gh issue list --state open --limit 10` | 아래 **이슈 우선순위 프로토콜** 참조 |
| 2. 계획 | 구현 전략을 내부적으로 수립 (텍스트 출력) | `EnterPlanMode`/`ExitPlanMode` 사용 금지 — 비대화형 세션에서 블로킹됨 |
| 3. 구현 → 검증 → 커밋 (반복) | 아래 **구현 루프** 참조 | 단위별로 즉시 커밋+푸시 |
| 4. 코드 리뷰 | `/review` — PRD 준수·메모리 안전성·테스트 커버리지 확인 | 이슈 발견 시 수정 후 재커밋 |
| 5. 릴리즈 판단 | 마일스톤 완료 또는 버그 수정 시 **자동 릴리즈** | 아래 **릴리즈 판단 프로토콜** 참조 |
| 6. 메모리 갱신 | `.claude/memory/` + `docs/milestones.md` 업데이트 | 별도 커밋: `chore: update session memory` → push |
| 7. 세션 요약 | 구조화된 요약 출력 | 아래 템플릿 참조 |

**구현 루프** (Phase 3 상세):

작업을 작은 단위로 분할하고, 각 단위마다 다음을 반복한다:
0. **Scratchpad 초기화** — `.claude/scratchpad.md`를 초기화 템플릿으로 덮어쓰기 (Shared Scratchpad Protocol 참조)
1. **Red** — `test-writer` 호출: 요구사항을 검증하는 실패하는 테스트 작성
2. **Green** — `zig-developer` 호출: 테스트를 통과시키는 최소한의 구현
3. **Refactor** — 테스트 통과 상태에서 코드 정리 (테스트 수정 필요 시 `test-writer` 재호출)
4. 즉시 커밋 + `git push` — 다음 단위로 넘어가기 전에 반드시 수행
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
| 3 (보통) | `feature-request` 라벨 + 현재 마일스톤 범위 내 | 현재 구현 중인 마일스톤의 추가 기능 |
| 4 (낮음) | `feature-request` 라벨 + 미래 마일스톤 | 아직 시작하지 않은 마일스톤의 기능 요청 |

**판단 규칙**:
- 우선순위 1-2 (버그): 마일스톤 작업보다 **항상 우선** 처리
- 우선순위 3 (현재 마일스톤 기능 요청): 마일스톤 작업과 **병행** — 같은 모듈 작업 시 함께 구현
- 우선순위 4 (미래 마일스톤 기능 요청): **적어두고 넘어감** — 해당 마일스톤 도달 시 처리
- 이슈를 처리한 후: `gh issue close <number> --comment "Fixed in <commit-hash>"`
- 이슈에 코멘트로 진행 상황 공유: `gh issue comment <number> --body "Working on this in current session"`

**릴리즈 판단 프로토콜** (Step 5):

세션 사이클의 **Step 5 (릴리즈 판단)** 에서 아래 조건을 확인하고, 충족 시 자율적으로 릴리즈를 수행한다.

### 버전 안전 규칙 (CRITICAL)

- **버전은 반드시 단조 증가**해야 한다. 새 버전은 `build.zig.zon`의 현재 버전보다 **반드시 높아야** 한다.
- 릴리즈 전 반드시 현재 버전을 확인: `grep 'version' build.zig.zon`
- 새 태그가 `git tag -l 'v*' --sort=-v:refname | head -1`보다 **낮으면 즉시 중단**.
- 버전 다운그레이드는 **절대 금지** — semver에서 1.15.0 → 1.0.0은 회귀이다.
- **버전 건너뛰기 금지**: 릴리즈 버전은 현재 `build.zig.zon` 버전의 **다음 마이너**여야 한다. 마일스톤에 미리 할당된 버전 번호가 있더라도, 실제 릴리즈 시점에는 현재 버전 + 1을 사용한다.
- **마일스톤은 이름(테마)으로 관리**: 버전 번호는 릴리즈 시점에 결정. 마일스톤 수립 시 미리 할당된 번호는 참고용.

```bash
# 릴리즈 판단 체크
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
git log ${LAST_TAG}..HEAD --oneline
gh issue list --state open --label bug --limit 5
```

**판단 로직**:
- 태그 이후 커밋 없음 → **SKIP** (릴리즈 불필요)
- `fix:` 커밋만 존재 → **PATCH** (v1.0.X)
- 마일스톤 완료 (`docs/milestones.md`에서 `[x]` 모두 체크) → **MINOR** (v1.X.0)
- **MAJOR** (v2.0.0) → 사용자 지시 시에만 수행

**공통 릴리즈 조건 (ALL must be true)**:
1. `zig build test` — 전체 통과, 0 failures
2. 6개 크로스 컴파일 타겟 빌드 성공
3. `bug` 라벨 이슈가 **0개** (open)

---

**패치 릴리즈 (v1.0.X)**:

버그 수정 커밋이 존재하지만 릴리즈 태그가 없을 때 즉시 발행한다.

**트리거 조건**:
- `from:*` 라벨 버그가 수정된 커밋이 존재하지만 릴리즈 태그가 없을 때
- 빌드/테스트 실패를 수정한 커밋
- 크로스 컴파일 깨짐을 수정한 커밋

**버전 규칙**:
- PATCH 번호만 증가 (예: v1.0.0 → v1.0.1)
- `build.zig.zon` version 수정 불필요 — 태그만으로 충분
- 기능 커밋을 패치에 포함하지 않음

**패치 릴리즈 절차**:
1. 버그 수정 커밋 식별 (예: `357fa25`)
2. `zig build test` 통과 확인
3. 태그: `git tag -a v1.0.X <commit-hash> -m "Release v1.0.X: <수정 요약>"`
4. 푸시: `git push origin v1.0.X`
5. GitHub Release: `gh release create v1.0.X --title "v1.0.X: <요약>" --notes "<릴리즈 노트>"`
6. 관련 이슈에 릴리즈 코멘트 추가
7. 소비자 프로젝트에 마이그레이션 이슈 발행 (아래 **Release & Consumer Migration Protocol** 참조)
8. Discord 알림: `openclaw message send --channel discord --target user:264745080709971968 --message "[sailor] Released v1.0.X — <요약>"`

---

**마이너 릴리즈 (v1.X.0)**:

`docs/milestones.md`의 마일스톤이 완료되었을 때 발행한다. 단순 feat 커밋만으로는 마이너 릴리즈하지 않는다.

**릴리즈 조건 (패치 조건 + 추가)**:
- 해당 마일스톤의 체크리스트 항목이 **모두 완료** (`[x]`)

**마이너 릴리즈 절차**:
1. `build.zig.zon`의 version 업데이트 (예: `"1.0.0"` → `"1.1.0"`)
2. `docs/milestones.md` 마일스톤 체크리스트에 완료 표시
3. 커밋: `chore: bump version to v1.X.0`
4. 태그: `git tag -a v1.X.0 -m "Release v1.X.0: <마일스톤 요약>"`
5. 푸시: `git push && git push origin v1.X.0`
6. GitHub Release 생성: `gh release create v1.X.0 --title "v1.X.0: <마일스톤 요약>" --notes "<릴리즈 노트>"`
7. 소비자 프로젝트에 마이그레이션 이슈 발행 (아래 **Release & Consumer Migration Protocol** 참조)
8. 관련 이슈 닫기: `gh issue close <number> --comment "Resolved in v1.X.0"`
9. Discord 알림: `openclaw message send --channel discord --target user:264745080709971968 --message "[sailor] Released v1.X.0 — <요약>"`
10. 관련 이슈에 릴리즈 코멘트 추가
11. **마일스톤 보충**: 미완료 마일스톤이 2개 이하이면 마일스톤 수립 프로세스 실행 (`docs/milestones.md` 참조)

**작업 선택 규칙**:
- `build.zig`가 없으면 프로젝트 부트스트랩부터 시작
- 이전 세션의 미커밋 변경사항이 있으면: 테스트 통과 시 커밋+푸시, 실패 시 폐기
- 테스트 실패 중이면 새 기능 추가 전에 수정
- 의존성 순서 준수: term → color → arg → repl → progress → fmt → tui
- 사이클당 하나의 집중 작업만 수행
- 이전 세션의 미완료 작업이 있으면 먼저 완료
- **GitHub 이슈 bug 라벨은 PRD 작업보다 항상 우선**

**테스트 품질 감사** (Stability 세션 필수):
- 무조건 통과하는 무의미한 테스트 식별 및 개선 (예: 빈 assertion, 항상 true인 조건)
- 구현 코드를 그대로 복사한 expected value 제거
- happy-path-only 테스트에 실패 시나리오 보강
- 경계값, 에러 경로, 동시성 시나리오 누락 확인
- `test-writer`를 호출하여 개선 방향 수립

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
- **Testing**: 모든 공개 함수는 구현 전에 실패하는 테스트를 먼저 작성한다 (TDD). 테스트는 커버리지가 아닌 실제 동작 검증에 집중한다
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

### Shared Scratchpad Protocol

개발 사이클(Red-Green-Refactor) 중 서브에이전트 간 협업을 위한 **임시 공유 메모리**이다.
영구 메모리(`.claude/memory/`)와 독립 운영되며, 기존 메모리 업데이트 규칙은 변경되지 않는다.

**파일**: `.claude/scratchpad.md` — `.gitignore`에 등록, git에 커밋하지 않는다

**대상 에이전트**: `test-writer`, `zig-developer`, `code-reviewer`

**라이프사이클**:
1. **사이클 시작** — 오케스트레이터가 `.claude/scratchpad.md`를 초기화 (기존 내용 덮어쓰기)
2. **에이전트 작업** — 각 에이전트가 작업 전 로드 → 작업 후 기록
3. **사이클 종료** — 다음 사이클 시작 시 다시 초기화

**규칙**:
1. **MUST LOAD**: 대상 에이전트는 작업 시작 시 `.claude/scratchpad.md`를 **반드시** 읽는다
2. **MUST WRITE**: 작업 완료 후 자신의 작업 내용을 **반드시** 추가한다
3. **NO DELETE**: 다른 에이전트의 기록을 삭제하지 않는다 (append-only)
4. **EPHEMERAL**: git에 커밋하지 않는다 — 사이클 내 협업이 목적
5. **NOT MEMORY**: 영구 보존이 필요한 인사이트는 `.claude/memory/`에 별도 기록 (기존 규칙 준수)

**초기화 템플릿** — 오케스트레이터가 사이클 시작 시 작성:

```markdown
# Scratchpad — [작업 설명]
> Cycle started: [timestamp]
> Goal: [이번 사이클의 목표]
---
```

**에이전트 기록 형식** — 작업 완료 후 append:

```markdown
## [agent-name] — [timestamp]
- **Did**: [수행한 작업]
- **Why**: [근거 / 의도]
- **Files**: [변경한 파일 목록]
- **For next**: [다음 에이전트가 알아야 할 사항]
- **Issues**: [발견한 문제점, 없으면 생략]
```

---

## zuda Library

- **Repository**: https://github.com/yusa-imit/zuda
- **Migration targets**: 없음 — sailor의 자료구조(Cell Buffer, Layout Solver, Grid, Unicode Width)는 TUI 특화이므로 zuda로 대체하지 않는다
- **Compatibility**: 소비자 프로젝트(zr, zoltraak, silica)가 zuda를 도입할 때 sailor와의 빌드 충돌이 없어야 한다

### zuda-first Policy (CRITICAL)
- 새로운 기능 구현 시 **범용** 데이터 구조/알고리즘이 필요하면, **zuda에 해당 모듈이 있는지 먼저 확인**한다
- TUI 특화 구조(위젯, 렌더링 버퍼, 레이아웃 등)는 해당하지 않음 — sailor 자체 구현 유지
- 범용 구조(정렬, 검색, 해시맵 변형, 그래프, 확률적 자료구조 등)는 zuda에 있으면 import하여 사용
- zuda에 없으면 → `gh issue create --repo yusa-imit/zuda --label "feature-request,from:sailor"` 발행 후 판단
- **범용 자료구조를 자체 구현하는 것은 최후의 수단**이다

### Issue Filing
- 호환성 문제: `gh issue create --repo yusa-imit/zuda --label "bug,from:sailor"`
- 기능 요청: `gh issue create --repo yusa-imit/zuda --label "feature-request,from:sailor"`

---

## Milestones & Dependencies

All 6 phases complete (v1.0.0). See `docs/PRD.md` for original requirements.

See `docs/milestones.md` for active milestones, completed releases, milestone establishment process, and dependency tracking (zuda compatibility).

---

## Test Execution Policy — 로컬 vs CI/Docker

로컬 머신에서 리소스 집약적 테스트(벤치마크, 스트레스 테스트, 크로스 컴파일 등)를 동시에 실행하면 메모리 압박으로 시스템 불안정(커널 패닉)을 유발할 수 있다. 다음 정책을 따른다:

### 로컬에서 실행 (OK)
- `zig build test` — 단위 테스트
- `zig build` — 단일 타겟 빌드
- `zig build example` — 예제 실행
- 빠른 검증 목적의 테스트

### CI(GitHub Actions)에서만 실행
- **크로스 컴파일**: 6개 타겟 동시 빌드
- **벤치마크**: `zig build benchmark` — 렌더링 성능 측정 및 회귀 감지
- **멀티 플랫폼 네이티브 테스트**: Linux x86_64, macOS x86_64/ARM64, Windows x86_64 동시 실행
- **성능 회귀 테스트**: PR별 벤치마크 비교

### cron 작업 규칙
- 로컬 cron에서 `zig build test`는 허용하되, 벤치마크/크로스 컴파일은 **금지** (Stabilization 세션 예외)
- 여러 Zig 프로젝트(zuda, zr, silica, zoltraak)의 cron이 동시에 실행될 수 있으므로, 로컬 cron은 경량 작업만 수행
- 무거운 검증은 `git push` 후 GitHub Actions에서 결과 확인

### Stabilization 세션 예외
- 실행 횟수 기반 판별 — `.claude/session-counter` 파일로 카운트
- 매 세션 시작 시: 카운터 읽기 → +1 → 저장 → `counter % 5 == 0`이면 Stabilization 세션
- 판별 로직:
  ```bash
  COUNTER_FILE=".claude/session-counter"
  COUNTER=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
  COUNTER=$((COUNTER + 1))
  echo "$COUNTER" > "$COUNTER_FILE"
  if [ $((COUNTER % 5)) -eq 0 ]; then echo "STABILIZATION"; else echo "NORMAL"; fi
  ```
- Stabilization 세션에서는 **크로스 컴파일**(6개 타겟) 및 **벤치마크** 로컬 실행 허용
- **동시 실행 금지**: 실행 전 다른 Zig 프로젝트의 heavy process가 없는지 확인 — `pgrep -f "zig build"` 결과가 없을 때만 진행
- 크로스 컴파일은 **순차 실행** (6개 타겟 동시 빌드 금지, 하나씩 실행)
- Stabilization이 아닌 일반 세션에서는 기존 정책 유지 (CI에서만 실행)

---

## Quick Reference

```bash
# Build library
zig build

# Test
zig build test

# Build and run example
zig build example -- hello

# Cross-compile check (CI에서만 전체 6 타겟 실행)
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
13. **Agent activity logging** — Subagent/Team 호출 시 반드시 `.claude/logs/agent-activity.jsonl`에 로그 기록 (아래 Agent Activity Logging 섹션 참조)
14. **TDD is mandatory** — 구현 전 반드시 `test-writer`로 실패하는 테스트를 작성. 테스트 수정 시에도 `test-writer` 재호출
15. **Meaningful tests only** — 무조건 통과하는 테스트, 구현을 복사한 테스트, assertion 없는 테스트 금지. 테스트가 실패할 수 있는 조건이 명확해야 한다

---

## Agent Activity Logging

Subagent(Task 도구) 또는 Team(TeamCreate)을 호출할 때마다 `.claude/logs/agent-activity.jsonl`에 로그를 기록한다.

**로그 형식** (JSON Lines — 한 줄에 하나의 JSON 객체):
```json
{"timestamp":"2026-03-14T12:00:00Z","action":"subagent","agent_type":"zig-developer","task":"Fix Tree widget rendering","project":"sailor"}
{"timestamp":"2026-03-14T12:05:00Z","action":"team_create","team_name":"v1.14-impl","members":["zig-developer","test-writer"],"task":"Implement v1.14.0 features","project":"sailor"}
{"timestamp":"2026-03-14T13:00:00Z","action":"team_delete","team_name":"v1.14-impl","project":"sailor"}
```

**필드**:

| 필드 | 필수 | 설명 |
|------|------|------|
| `timestamp` | ✅ | ISO 8601 형식 (UTC) |
| `action` | ✅ | `subagent` \| `team_create` \| `team_delete` |
| `agent_type` | subagent 시 | 에이전트 타입 (`zig-developer`, `code-reviewer`, `Explore` 등) |
| `team_name` | team 시 | 팀 이름 |
| `members` | team_create 시 | 팀 멤버 이름 배열 |
| `task` | ✅ | 작업 설명 (Task 도구의 description 또는 prompt 요약) |
| `project` | ✅ | 프로젝트 이름 (`sailor`) |

**규칙**:
1. `.claude/logs/` 디렉토리가 없으면 생성
2. 파일에 append (기존 로그 유지)
3. 로그는 git에 커밋+push 필수 — 커밋 메시지: `chore: update agent activity log`
4. 세션 종료 전 미커밋 로그가 있으면 반드시 커밋+push

---

## Release & Consumer Migration Protocol

sailor는 세 프로젝트(zr, zoltraak, silica)의 공유 라이브러리다. 버전 릴리즈 시 소비자 프로젝트에 GitHub 이슈로 마이그레이션을 알린다.

### 릴리즈 시 필수 절차

새 버전 태그 후, 각 소비자 프로젝트의 GitHub 리포지토리에 `migration` 라벨 이슈를 발행한다:

```bash
# 소비자 프로젝트에 마이그레이션 이슈 발행
for repo in zr zoltraak silica; do
  gh issue create --repo yusa-imit/$repo \
    --title "chore: migrate to sailor v1.X.0" \
    --label "migration,from:sailor" \
    --body "## sailor v1.X.0 릴리즈 알림

sailor v1.X.0이 릴리즈되었습니다. CLAUDE.md의 Sailor Migration 섹션에서 해당 버전 status를 READY로 변경하고 마이그레이션을 수행해주세요.

## 새 기능
- <주요 변경사항 요약>

## 마이그레이션 가이드
1. \`zig fetch --save https://github.com/yusa-imit/sailor/archive/refs/tags/v1.X.0.tar.gz\`
2. \`zig build test\` 통과 확인
3. CLAUDE.md에서 해당 버전 status: PENDING → DONE 변경

## Breaking Changes
- <있으면 기재, 없으면 '없음'>"
done
```

### 발행 규칙

1. 릴리즈 후 **각 소비자 프로젝트에 GitHub 이슈**를 발행한다 (`migration,from:sailor` 라벨)
2. 소비자 프로젝트의 CLAUDE.md를 **직접 수정하지 않는다**
3. 소비자 프로젝트의 에이전트가 `migration` 라벨 이슈를 감지하여 자체적으로 마이그레이션 수행
4. **코드 마이그레이션은 하지 않는다** — 소비자 프로젝트의 에이전트가 자체적으로 수행

### 버전별 소비자 마이그레이션 매핑

| sailor 버전 | zr | zoltraak | silica |
|------------|-----|----------|--------|
| v0.1.0 | arg, color 마이그레이션 | `parseArgs()` → `sailor.arg`, 서버 로그 color | CLI 플래그 추가 |
| v0.2.0 | progress 마이그레이션 | REPL 빌드 (`zoltraak-cli`) | SQL 셸 스켈레톤 |
| v0.3.0 | JSON output → sailor.fmt | 결과 포매팅 | `.mode table/csv/json` |
| v0.4.0 | TUI 마이그레이션 (태스크 피커, 라이브 러너) | 키 브라우저, 데이터 뷰어 | 스키마 브라우저, 결과 테이블 |
| v0.5.0 | 의존성 트리, 차트 | 모니터링 대시보드 | 쿼리 플랜 시각화 |

---

