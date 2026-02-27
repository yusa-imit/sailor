Fix a bug in the sailor library.

Bug description: $ARGUMENTS

Workflow:
1. **Reproduce**: Understand the bug. If a test reproduces it, run it.
2. **Locate**: Use Grep/Glob to find relevant code. Read the source files.
3. **Analyze**: Identify root cause. Check `.claude/memory/debugging.md` for similar past issues.
4. **Fix**: Apply the minimal fix needed. Don't refactor unrelated code.
5. **Test**: Ensure existing tests still pass. Add a regression test for this bug.
6. **Consumer check**: Verify fix doesn't break API compatibility with zr, zoltraak, silica.
7. **Verify**: Run `zig build test` to confirm everything passes.
8. **Memory**: Record the bug and fix in `.claude/memory/debugging.md`.
9. **Report**: Summarize the root cause, the fix, and the regression test added.
