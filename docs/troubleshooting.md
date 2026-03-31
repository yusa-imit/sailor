# Troubleshooting sailor

This guide covers common issues and their solutions when working with sailor.

## Build Issues

### Error: `unable to find 'sailor'`

**Problem**: Your build can't find the sailor dependency.

**Solution**: Ensure `build.zig.zon` has the correct dependency declaration:

```zig
.dependencies = .{
    .sailor = .{
        .url = "https://github.com/yusa-imit/sailor/archive/refs/tags/v1.26.0.tar.gz",
        .hash = "<hash>",
    },
},
```

Run `zig build` once to generate the hash, then add it to `.zon`.

### Error: `hash mismatch`

**Problem**: The dependency hash doesn't match.

**Solution**: Delete the hash from `build.zig.zon` and run `zig build` again. Zig will fetch the dependency and show you the correct hash.

### Error: `target OS not supported`

**Problem**: sailor uses platform-specific APIs.

**Solution**: sailor supports Linux, macOS, and Windows. Ensure you're building for one of these targets:

```bash
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=x86_64-macos
zig build -Dtarget=x86_64-windows-msvc
```

## Runtime Issues

### Colors don't appear

**Problem**: ANSI colors not rendering.

**Possible causes**:

1. **NO_COLOR environment variable is set**:
   ```bash
   unset NO_COLOR
   ```

2. **Terminal doesn't support colors**:
   ```zig
   const depth = try sailor.color.detectColorSupport(allocator);
   std.debug.print("Color depth: {}\n", .{depth});
   // Should print: truecolor, indexed256, basic16, or none
   ```

3. **Not running in a TTY** (output redirected):
   ```zig
   const is_tty = try sailor.term.isatty(std.io.getStdOut().handle);
   if (!is_tty) {
       // Output is redirected, colors disabled
   }
   ```

**Solution**: Check terminal capability or set `COLORTERM=truecolor` environment variable.

### Terminal size returns (0, 0)

**Problem**: `getSize()` returns zero dimensions.

**Possible causes**:

1. **Not running in a TTY**:
   ```zig
   const is_tty = try sailor.term.isatty(std.io.getStdOut().handle);
   if (!is_tty) {
       // Use default fallback size
       const size = .{ .cols = 80, .rows = 24 };
   }
   ```

2. **Windows console issues**: On Windows, ensure you're using a modern terminal (Windows Terminal, not cmd.exe).

**Solution**: Always check if running in a TTY before calling `getSize()`, and provide fallback dimensions.

### Raw mode doesn't work

**Problem**: `RawMode.init()` fails or doesn't capture key presses.

**Possible causes**:

1. **Not running in a TTY**:
   ```zig
   const is_tty = try sailor.term.isatty(std.io.getStdIn().handle);
   if (!is_tty) return error.NotATty;
   ```

2. **Already in raw mode**: Calling `RawMode.init()` twice without `deinit()`:
   ```zig
   var raw = try sailor.term.RawMode.init(stdin);
   defer raw.deinit(); // MUST call deinit() to restore terminal
   ```

3. **Signal handling**: Ctrl+C kills process before cleanup:
   ```zig
   // Handle signals properly
   var raw = try sailor.term.RawMode.init(stdin);
   errdefer raw.deinit(); // Cleanup on error
   defer raw.deinit();
   ```

**Solution**: Always use `defer raw.deinit()` and check for TTY before entering raw mode.

### readKey() hangs indefinitely

**Problem**: `readKey()` blocks forever.

**Cause**: Reading from stdin without timeout.

**Solution**: Use `pollEvent()` with timeout in TUI applications:

```zig
// Instead of:
const key = try sailor.term.readKey(stdin);

// Use:
if (try term.pollEvent(100)) |event| {
    switch (event) {
        .key => |key| {
            // Handle key
        },
        else => {},
    }
}
```

## TUI Issues

### Screen doesn't clear properly

**Problem**: Previous output visible after TUI exits.

**Solution**: Always call `leaveAlternateScreen()` on cleanup:

```zig
var term = try sailor.tui.Terminal.init(allocator);
defer term.deinit();

try term.enterAlternateScreen();
defer term.leaveAlternateScreen() catch {}; // Use catch {} in defer

// ... TUI code ...
```

### Cursor still visible in TUI

**Problem**: Cursor blinks in the interface.

**Solution**: Hide cursor during rendering:

```zig
try term.hideCursor();
defer term.showCursor() catch {};

// ... render loop ...
```

### Flickering/tearing during updates

**Problem**: Screen flickers on redraw.

**Possible causes**:

1. **No double buffering**: sailor automatically buffers, but you might be calling multiple `draw()` per frame.

   **Solution**: Call `term.draw()` once per frame:
   ```zig
   // Good
   while (true) {
       try term.draw(drawUI);
       // ... handle events ...
   }

   // Bad - multiple draws per loop
   while (true) {
       try term.draw(drawHeader);
       try term.draw(drawBody);  // Causes flicker
   }
   ```

2. **Not using synchronized output**: For terminals that support it:
   ```zig
   try term.enableSyncOutput();
   defer term.disableSyncOutput() catch {};
   ```

3. **Rendering too fast**: Add frame rate limiting:
   ```zig
   const frame_time = 1000 / 60; // 60 FPS
   const start = std.time.milliNow();

   try term.draw(drawUI);

   const elapsed = std.time.milliNow() - start;
   if (elapsed < frame_time) {
       std.time.sleep((frame_time - elapsed) * std.time.ns_per_ms);
   }
   ```

### Widget not rendering

**Problem**: Widget appears empty or invisible.

**Possible causes**:

1. **Area too small**: Widget has no space to render.
   ```zig
   // Check area before rendering
   if (area.width == 0 or area.height == 0) return;
   ```

2. **Style matches background**: Text color same as background.
   ```zig
   const style = .{ .fg = .{ .basic = .white }, .bg = .{ .basic = .black } };
   ```

3. **Widget outside viewport**: Rendering outside buffer bounds.
   ```zig
   // Ensure widget is within frame size
   const area = frame.size();
   const widget_area = .{
       .x = 0,
       .y = 0,
       .width = @min(area.width, 80),
       .height = @min(area.height, 24),
   };
   ```

### Layout constraints not working as expected

**Problem**: Layout splits don't match percentages.

**Cause**: Constraints must sum to fill available space.

**Solution**: Verify constraint total:

```zig
// Good - adds up to 100%
.constraints(&.{
    .{ .percentage = 30 },
    .{ .percentage = 70 },
})

// Bad - adds up to 150%
.constraints(&.{
    .{ .percentage = 50 },
    .{ .percentage = 100 },
})
```

For mixed constraints:
```zig
// Fixed header + flexible body + fixed footer
.constraints(&.{
    .{ .length = 3 },      // Header: 3 lines
    .{ .min = 10 },        // Body: at least 10 lines, fills remaining
    .{ .length = 1 },      // Footer: 1 line
})
```

## Memory Issues

### Memory leak detected

**Problem**: GPA reports memory leaks on exit.

**Possible causes**:

1. **Forgot to call `deinit()`**:
   ```zig
   var term = try sailor.tui.Terminal.init(allocator);
   defer term.deinit(); // REQUIRED
   ```

2. **Widget resources not freed**:
   ```zig
   var list = try sailor.tui.widgets.List.init(allocator);
   defer list.deinit(); // REQUIRED if widget allocates
   ```

3. **Theme or buffer not freed**:
   ```zig
   var theme = try sailor.tui.Theme.load(allocator, "theme.json");
   defer theme.deinit(); // REQUIRED
   ```

**Solution**: Use `defer` immediately after allocation, and run with GPA in debug mode to catch leaks.

### Out of memory errors

**Problem**: Allocation fails with `OutOfMemory`.

**Possible causes**:

1. **Large buffer allocations**: TUI buffers can be large for big terminals.

   **Solution**: Use arena allocator for frame-scoped allocations:
   ```zig
   var arena = std.heap.ArenaAllocator.init(gpa.allocator());
   defer arena.deinit();
   const frame_alloc = arena.allocator();

   // Use frame_alloc for temporary allocations during rendering
   ```

2. **Memory leak in render loop**: Allocating without freeing each frame.

   **Solution**: Reset arena at start of each frame:
   ```zig
   while (true) {
       defer _ = arena.reset(.retain_capacity);
       try term.draw(drawUI);
   }
   ```

3. **Unbounded history/cache**: REPL history or data lists growing indefinitely.

   **Solution**: Set limits:
   ```zig
   var repl = try sailor.repl.Repl.init(allocator, .{
       .max_history = 1000, // Limit history size
   });
   ```

## Performance Issues

### TUI is slow/laggy

**Problem**: Rendering takes too long, input is unresponsive.

**Possible causes**:

1. **Rendering entire screen every frame**:

   **Solution**: sailor automatically diffs buffers, but minimize work in draw callback:
   ```zig
   fn drawUI(frame: *sailor.tui.Frame) !void {
       // Don't do heavy computation here
       // Prepare data before calling term.draw()
   }
   ```

2. **Too many widgets**: Rendering hundreds of widgets per frame.

   **Solution**: Use virtual rendering for lists/tables:
   ```zig
   var list = sailor.tui.widgets.List.init(allocator);
   list.setVirtualization(true); // Only render visible items
   ```

3. **No frame rate limiting**: Rendering as fast as possible.

   **Solution**: Add sleep between frames (see flickering section above).

### Slow startup time

**Problem**: Application takes seconds to start.

**Possible causes**:

1. **Large data loading**: Reading files or databases on startup.

   **Solution**: Load data asynchronously after TUI is shown:
   ```zig
   try term.draw(drawLoadingScreen);

   // Load data
   const data = try loadData(allocator);

   // Continue with normal rendering
   ```

2. **Theme compilation**: Loading complex themes.

   **Solution**: Use precompiled themes or cache parsed themes.

## Argument Parsing Issues

### Unknown flag error

**Problem**: Valid flags reported as unknown.

**Cause**: Flag not defined in comptime flags array.

**Solution**: Ensure all flags are defined:

```zig
const flags = comptime &[_]sailor.arg.Flag{
    .{ .name = "verbose", .short = 'v', .type = .bool, .help = "..." },
    .{ .name = "output", .short = 'o', .type = .string, .help = "..." },
    // Add all valid flags here
};
```

### Type mismatch when getting flag value

**Problem**: `get()` returns wrong type or error.

**Cause**: Requesting wrong type for flag.

**Solution**: Match `get()` type to flag definition:

```zig
// Flag defined as .bool
.{ .name = "verbose", .type = .bool, ... }

// Get as bool (not string or int)
const verbose = try result.get("verbose", bool) orelse false;
```

### Positional args not captured

**Problem**: `result.positional` is empty.

**Cause**: Arguments might be parsed as flags.

**Solution**: Check flag definitions and use `--` to separate:

```bash
# Everything after -- is positional
myapp --verbose -- file1.txt file2.txt
```

## REPL Issues

### History not persisting

**Problem**: Command history lost between sessions.

**Cause**: History file path not writable or not specified.

**Solution**: Specify history file and ensure directory exists:

```zig
var repl = try sailor.repl.Repl.init(allocator, .{
    .history_file = "/home/user/.myapp_history", // Absolute path
});
```

### Tab completion not working

**Problem**: Pressing Tab doesn't complete.

**Cause**: Completion callback not set.

**Solution**: Provide completion function:

```zig
fn complete(input: []const u8, allocator: std.mem.Allocator) ![]const []const u8 {
    // Return list of completions for input
    if (std.mem.startsWith(u8, "help", input)) {
        return &.{"help"};
    }
    return &.{};
}

var repl = try sailor.repl.Repl.init(allocator, .{
    .completion = complete,
});
```

## Platform-Specific Issues

### Windows: Colors not working

**Problem**: Colors appear as garbled text on Windows.

**Solution**: Enable ANSI escape sequence processing:

```zig
// sailor does this automatically, but if it fails:
// Use Windows Terminal instead of cmd.exe
// Or enable Virtual Terminal Processing manually
```

### macOS: Alt key not working

**Problem**: Alt+key combinations not detected.

**Cause**: Terminal.app sends different escape sequences.

**Solution**: Use iTerm2 or enable "Use Option as Meta key" in Terminal.app preferences.

### Linux: Terminal size wrong after resize

**Problem**: `SIGWINCH` not handled.

**Solution**: sailor handles `SIGWINCH` automatically in `pollEvent()`. Ensure you're using event polling:

```zig
if (try term.pollEvent(100)) |event| {
    switch (event) {
        .resize => |size| {
            // Terminal resized, sailor updates automatically
        },
        else => {},
    }
}
```

## Debug Tips

### Enable debug logging

Set environment variable before running:

```bash
SAILOR_DEBUG=1 ./myapp
```

### Check terminal capabilities

Use `termcap` module to query terminal:

```zig
const termcap = try sailor.termcap.TermInfo.init(allocator);
defer termcap.deinit();

const has_colors = termcap.getBoolean("colors");
const max_colors = termcap.getNumber("colors");
const acs = termcap.getString("acs");

std.debug.print("Colors: {}, Max: {}, ACS: {s}\n", .{
    has_colors, max_colors, acs orelse "<none>",
});
```

### Inspect buffer contents

In debug builds, you can dump the buffer:

```zig
try frame.buffer.dump(std.io.getStdErr().writer());
```

### Memory profiling

Run with GPA and track allocations:

```bash
zig build -Doptimize=Debug
./zig-out/bin/myapp

# Check for leaks on exit
# GPA will print leak report automatically
```

## Getting Help

If you've tried these solutions and still have issues:

1. Check GitHub Issues: https://github.com/yusa-imit/sailor/issues
2. Create a minimal reproduction case
3. Include:
   - Zig version (`zig version`)
   - sailor version
   - Platform (Linux/macOS/Windows + terminal emulator)
   - Error messages or unexpected behavior
   - Code snippet demonstrating the issue

## Known Limitations

- **Windows**: Some advanced terminal protocols (Sixel, Kitty graphics) not supported
- **SSH**: Graphics protocols may not work over SSH without proper terminal forwarding
- **Screen/tmux**: Some features require recent versions with extended capabilities
- **Color depth**: Detection is best-effort; override with `COLORTERM=truecolor` if needed
- **Unicode width**: CJK and emoji width follows UAX #11; some terminals may differ
