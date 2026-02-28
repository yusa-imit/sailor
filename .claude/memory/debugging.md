# Sailor Debugging Notes

## Fixed Issues

### UTF-8 Handling in Buffer.setString (2026-02-28)
**Symptom**: Emoji and CJK characters rendered as individual bytes instead of proper Unicode codepoints.
**Root Cause**: `Buffer.setString()` was iterating byte-by-byte instead of decoding UTF-8 sequences.
**Fix**: Use `std.unicode.utf8ByteSequenceLength()` and `std.unicode.utf8Decode()` to properly extract codepoints.
**Test Coverage**: Added 6 edge case tests for Unicode, CJK, zero-width chars, boundaries.

## Known Zig 0.15.x Gotchas (from zr experience)
- `std.ArrayList(T){}` not `.init(allocator)` — unmanaged API
- `std.Thread.sleep(ns)` not `std.time.sleep`
- `child.wait()` closes stdout — read stdout BEFORE wait()
- `callconv(.c)` lowercase in 0.15
- Buffered writers: flush before `std.process.exit()`
- File-scope: `const X = expr;` (no `comptime` keyword — redundant error)
- `zig build test` uses `--listen=-` protocol — NEVER use `stdout()` in test code
