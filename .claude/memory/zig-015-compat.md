# Zig 0.15.x API Compatibility Notes

## builtin module changes
- `builtin.strip` removed → use `builtin.mode != .Debug`
- `builtin.stack_protector` removed → safety is mode-dependent
- `builtin.sanitize_c` removed → use `@hasDecl` check
- `builtin.object_format`: `.pe` removed, use `.coff` for Windows
- `builtin.target.cpu.arch.ptrBitWidth()` removed → use `@bitSizeOf(usize)`
- `builtin.dynamic_linker` → now `builtin.target.dynamic_linker.get()`

## std.mem changes
- `std.mem.page_size` removed → use constant or runtime detection

## std.ArrayList API breaking changes
- Old: `ArrayList(T).init(allocator)` + `defer list.deinit()`
- New: `var list: ArrayList(T) = .{}` + `defer list.deinit(allocator)`
- Methods now require allocator: `list.append(allocator, item)`
- Writer now requires allocator: `list.writer(allocator)`

## std.mem.Allocator changes
- `alignedAlloc(T, comptime alignment: usize, n)`
- → `alignedAlloc(T, alignment: std.mem.Alignment, n)`
- Use `@enumFromInt(log2_alignment)` for conversion (e.g., `@enumFromInt(4)` for 16-byte alignment)

## std.io changes
- `std.io.getStdIn/Out/Err()` API changed in 0.15.x
- Tests now just verify `std.io` namespace exists
