Prepare and execute a release for the sailor library.

Version: $ARGUMENTS (e.g., "v0.1.0")

Workflow:
1. **Pre-flight checks**:
   - Run `zig build test` — all tests must pass
   - Run `git status` — working tree must be clean
   - Cross-compile for all 6 targets to verify builds
2. **Version bump**: Update version in `build.zig.zon`
3. **Changelog**: Generate summary of changes since last tag
4. **Commit**: Commit version bump with `chore: bump version to <version>`
5. **Tag**: Create annotated tag
6. **Push**: Push commit + tag
7. **Notify consumers**: Note which consumer projects (zr, zoltraak, silica) should update their dependency hash
8. **Report**: Summary of release steps completed

Note: Actual tagging and pushing should be confirmed with user before execution.
