Perform a code review on current changes.

Steps:
1. Run `git diff` to see unstaged changes
2. Run `git diff --cached` to see staged changes
3. If no changes, check `git diff HEAD~1` for the last commit
4. For each changed file:
   a. Read the full file for context
   b. Review changes against the checklist:
      - Correctness: Does the logic match PRD specifications?
      - Library safety: No global state, no stdout, no panic, writer-based API?
      - API quality: Minimal, intuitive, comptime-validated?
      - Cross-platform: Platform code isolated in term.zig?
      - Tests: Are there tests for new/changed functionality?
      - Performance: Efficient rendering, minimal allocations in hot paths?
5. Report findings as CRITICAL / WARNING / SUGGESTION

Context: $ARGUMENTS (optional description of what to focus on)
