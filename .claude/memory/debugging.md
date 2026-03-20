# Sailor Debugging Notes

## Fixed Issues

### Markdown Widget Ambiguous Reference and ArrayList API (2026-03-20)
**Symptom**: Compilation errors blocking all tests:
  1. Ambiguous reference to `Node` type in markdown.zig
  2. ArrayList.init() method doesn't exist in Zig 0.15
  3. ArrayList.deinit() and append() missing allocator parameter
**Root Cause**:
  1. Duplicate `Node` type declarations: module-level + struct-level re-export created conflict
  2. Unmanaged ArrayList API in Zig 0.15 requires explicit allocator for all operations
**Fix**:
  1. Use module reference `const markdown_mod = @This()` and qualified names `markdown_mod.Node` internally
  2. ArrayList initialization: `ArrayList(T){}` not `.init(allocator)`
  3. Add allocator parameter: `lines.deinit(self.allocator)` and `lines.append(self.allocator, item)`
**Test Coverage**: All compilation errors resolved, cross-compilation verified (Linux, Windows)
**Commits**: e2b9d74, 12c83a6

### Calendar Date Arithmetic and Navigation Constraints (2026-03-19)
**Symptom**: Test failures in Calendar widget:
  1. `addMonths()` incorrectly calculated month 10 + 5 months → month 4 instead of month 3
  2. `nextYear()` didn't respect `max_date` constraint, allowing navigation beyond boundaries
**Root Cause**:
  1. Year-wrapping logic used `(12 - month)` instead of `(12 - month + 1)` to account for jumping to January
  2. Navigation methods (`nextYear`, `prevYear`, `nextMonth`, `prevMonth`) lacked constraint checking
**Fix**:
  1. Corrected arithmetic: when at month 10 adding 5, consume 3 months to reach next January, leaving 2 to add → month 3
  2. Added min/max date boundary checks in all navigation methods
**Test Coverage**:
  - "Date.addMonths wraps to next year" now passes
  - "Calendar prevents navigation with min/max year constraints" now passes
**Commit**: a5fcd8f

### UTF-8 Handling in Menu Widget Submenu Indicators (2026-03-18)
**Symptom**: Unicode submenu indicator '▶' rendered as byte 226 instead of codepoint 9654.
**Root Cause**: `Menu.renderItems()` iterated over `submenu_indicator` as bytes (`for (self.submenu_indicator) |c|`), treating UTF-8 multi-byte sequences as individual characters.
**Fix**: Use `std.unicode.Utf8View.init()` and iterator to decode codepoints properly.
**Impact**: Render function signature changed to `!void` to handle UTF-8 validation errors.
**Test Coverage**: Existing test "Menu.render with custom unicode submenu indicator" now passes.
**Commit**: 578a46f

### UTF-8 Handling in Buffer.setString (2026-02-28)
**Symptom**: Emoji and CJK characters rendered as individual bytes instead of proper Unicode codepoints.
**Root Cause**: `Buffer.setString()` was iterating byte-by-byte instead of decoding UTF-8 sequences.
**Fix**: Use `std.unicode.utf8ByteSequenceLength()` and `std.unicode.utf8Decode()` to properly extract codepoints.
**Test Coverage**: Added 6 edge case tests for Unicode, CJK, zero-width chars, boundaries.

## Known Zig 0.15.x Gotchas (from zr experience)
- `std.ArrayList(T){}` not `.init(allocator)` — unmanaged API
- ArrayList methods need allocator: `list.deinit(allocator)`, `list.append(allocator, item)`
- `std.Thread.sleep(ns)` not `std.time.sleep`
- `child.wait()` closes stdout — read stdout BEFORE wait()
- `callconv(.c)` lowercase in 0.15
- Buffered writers: flush before `std.process.exit()`
- File-scope: `const X = expr;` (no `comptime` keyword — redundant error)
- `zig build test` uses `--listen=-` protocol — NEVER use `stdout()` in test code
- Ambiguous type references: Use module-level references (`const mod = @This()`) when re-exporting types
