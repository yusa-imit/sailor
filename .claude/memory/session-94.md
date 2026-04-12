# Project Context — sailor

Last updated: 2026-04-13 (Session 94)

## 🎉 Session 94 — FEATURE MODE: v2.0.0 MAJOR RELEASE (2026-04-13)

**Mode**: FEATURE (session 94, 94 % 5 == 4)

**Major Achievement**: Successfully released v2.0.0 — Major API Cleanup & Modernization

### Breaking Changes Implemented

1. ✅ **Removed `Buffer.setChar()`**
   - Migrated all internal usages (dialog.zig, test files)
   - Removed deprecated method from buffer.zig
   - Updated tests: "Buffer.setChar" → "Buffer.set"

2. ✅ **Removed `Rect.new()`**
   - Ran migration script on tests/ and examples/
   - All 270+ usages migrated to struct literals
   - Removed deprecated constructor method

3. ✅ **Block.withTitle() Decision**
   - Removed deprecation warning (kept as valid builder pattern)
   - Reason: Enables fluent chaining, widely used, idiomatic Zig

### Release Process Executed

1. ✅ Version bump: 1.38.0 → 2.0.0 (build.zig.zon)
2. ✅ Git tag and GitHub release created
3. ✅ Migration issues filed: zr, zoltraak, silica
4. ✅ Discord notification sent

### Test Results

- **All 3345+ tests passing**
- Zero regressions

### Current State

- **Latest release**: v2.0.0 (2026-04-13)
- **Next milestone**: v2.1.0 (Post-v2.0 Polish & Consumer Feedback)
- **Active milestones**: 1 (v2.1.0)

---

