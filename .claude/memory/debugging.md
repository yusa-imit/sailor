# Sailor Debugging Notes

(No issues yet — project bootstrapping)

## Known Zig 0.15.x Gotchas (from zr experience)
- `std.ArrayList(T){}` not `.init(allocator)` — unmanaged API
- `std.Thread.sleep(ns)` not `std.time.sleep`
- `child.wait()` closes stdout — read stdout BEFORE wait()
- `callconv(.c)` lowercase in 0.15
- Buffered writers: flush before `std.process.exit()`
- File-scope: `const X = expr;` (no `comptime` keyword — redundant error)
- `zig build test` uses `--listen=-` protocol — NEVER use `stdout()` in test code
