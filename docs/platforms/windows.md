# sailor on Windows

This guide covers using sailor on Windows 10+ systems, including setup, terminal emulator recommendations, and platform-specific quirks.

## Quick Start

### Prerequisites

- **Windows 10** (build 1809+) or **Windows 11** for best experience
- **Zig 0.15.2+** ([download](https://ziglang.org/download/))
- **Windows Terminal** (recommended) or modern terminal emulator

### Installation

1. Add sailor to your `build.zig.zon`:

```zig
.dependencies = .{
    .sailor = .{
        .url = "https://github.com/yusa-imit/sailor/archive/refs/tags/v2.7.0.tar.gz",
        .hash = "...", // zig fetch will provide this
    },
},
```

2. Run `zig fetch --save https://github.com/yusa-imit/sailor/archive/refs/tags/v2.7.0.tar.gz`

3. Import in your `build.zig`:

```zig
const sailor = b.dependency("sailor", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("sailor", sailor.module("sailor"));
```

## Recommended Terminal Emulators

### Windows Terminal (Best)

**Download**: [Microsoft Store](https://aka.ms/terminal) or [GitHub Releases](https://github.com/microsoft/terminal/releases)

**Why**: Native ConPTY support, full ANSI escape sequence support, GPU-accelerated rendering, excellent Unicode handling.

**Configuration**:
```json
{
    "profiles": {
        "defaults": {
            "font": {
                "face": "Cascadia Code",
                "size": 10
            },
            "colorScheme": "One Half Dark"
        }
    }
}
```

**Truecolor Test**:
```bash
zig build example -- hello
```
You should see full 24-bit RGB colors without banding.

### WezTerm (Cross-Platform Alternative)

**Download**: [wezfurlong.org/wezterm](https://wezfurlong.org/wezterm/)

**Why**: Cross-platform consistency, extensive customization, Lua configuration.

**Configuration** (`wezterm.lua`):
```lua
return {
  color_scheme = "Dracula",
  font = wezterm.font("JetBrains Mono"),
  font_size = 10.0,
  enable_tab_bar = false,
}
```

### Alacritty (Lightweight)

**Download**: [alacritty.org](https://alacritty.org/)

**Why**: Minimal resource usage, GPU-accelerated, fast startup.

**Caveat**: Requires manual configuration for fonts/colors (no GUI settings).

### Avoid

- **cmd.exe** — Limited ANSI support, no truecolor
- **PowerShell 5.1 console** — Poor Unicode rendering, slow
- **Old ConHost** (pre-Windows 10 1809) — No VT100 support

## Windows vs WSL

sailor works on **both native Windows and WSL** with different trade-offs:

### Native Windows

**Pros**:
- Better integration with Windows APIs (clipboard, console)
- No Linux subsystem overhead
- Direct filesystem access

**Cons**:
- Path separator differences (`\` vs `/`)
- Environment variable differences (`%VAR%` vs `$VAR`)
- Requires PowerShell/Windows Terminal for best experience

**Example** (`build.zig`):
```zig
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;

const path_separator = if (is_windows) "\\" else "/";
```

### WSL (Windows Subsystem for Linux)

**Pros**:
- Linux environment (familiar tooling)
- Better shell support (bash, zsh)
- Native Zig Linux builds

**Cons**:
- Slight performance overhead
- Clipboard integration requires extra tools (`xclip`, `wl-clipboard`)
- Filesystem access to Windows drives can be slow

**Recommendation**: Use **native Windows** for production builds, WSL for development if you prefer Linux tooling.

## Platform-Specific Features

### Windows Console API

sailor automatically detects Windows and uses native console APIs:

```zig
const sailor = @import("sailor");

pub fn main() !void {
    // Automatically uses Windows Console API on Windows
    const term = try sailor.term.Terminal.init();
    defer term.deinit();

    // ConPTY mode on Windows Terminal (fast ANSI passthrough)
    // Legacy mode on older consoles (ANSI emulation)
}
```

**Detection Logic**:
- Windows Terminal / ConPTY: Direct ANSI sequence emission (zero overhead)
- Legacy console: Buffered console API calls with ANSI emulation

### Clipboard (OSC 52 + PowerShell)

sailor supports clipboard operations on Windows via:

1. **OSC 52** (Windows Terminal, WezTerm) — terminal-based clipboard
2. **PowerShell** (`Set-Clipboard`, `Get-Clipboard`) — system clipboard

**Example**:
```zig
const clipboard = sailor.clipboard.SystemClipboard.init();
if (clipboard.isAvailable()) {
    try clipboard.write("Hello from sailor", allocator);
    const text = try clipboard.read(allocator);
    defer allocator.free(text);
}
```

### UTF-16 Encoding

Windows console uses **UTF-16** internally, but sailor handles this transparently:

```zig
// sailor converts UTF-8 → UTF-16 automatically
try term.writeAll("Unicode: 你好 🌊 مرحبا"); // Works on Windows
```

### Keyboard Events

sailor maps Windows-specific keys:

| Windows Key | Event | Notes |
|-------------|-------|-------|
| Ctrl+C | `.interrupt` | Handled by sailor (no SIGINT on Windows) |
| Alt+F4 | `.close` | Window close request |
| Ctrl+Z | `.suspend` | Emulated (no job control on Windows) |

## Known Quirks

### 1. Slow ANSI Parsing on Legacy Consoles

**Symptom**: Slow rendering on old Windows 7/8 consoles.

**Cause**: sailor emulates ANSI escape sequences via console API calls.

**Fix**: Upgrade to **Windows Terminal** or **ConPTY-enabled console**.

**Detection** (automatic):
```zig
const quirks = sailor.tui.quirks.detect();
if (quirks.is_legacy_windows) {
    // sailor batches console API calls automatically
}
```

### 2. Clipboard Padding (PowerShell)

**Symptom**: OSC 52 clipboard writes fail silently.

**Cause**: PowerShell `Set-Clipboard` requires base64 padding.

**Fix**: sailor handles this automatically via quirks database.

**Code** (internal):
```zig
if (quirks.clipboard_needs_padding) {
    // Add '=' padding to base64 for PowerShell compatibility
}
```

### 3. Line Endings (CRLF)

**Symptom**: Extra blank lines in text output.

**Cause**: Windows uses `\r\n` line endings, sailor emits `\n`.

**Fix**: sailor normalizes line endings automatically for text widgets.

**Manual Handling**:
```zig
const line_ending = if (builtin.os.tag == .windows) "\r\n" else "\n";
```

### 4. Path Separators

**Symptom**: File paths with `/` fail on Windows.

**Cause**: Windows uses `\` as path separator.

**Fix**: Use `std.fs.path.join()` or sailor's path helpers:

```zig
const path = try std.fs.path.join(allocator, &.{"logs", "sailor.log"});
// Windows: "logs\sailor.log"
// Linux:   "logs/sailor.log"
```

### 5. No SIGWINCH

**Symptom**: Terminal resize events not detected.

**Cause**: Windows doesn't have SIGWINCH signal.

**Fix**: sailor polls terminal size on Windows (every 100ms in event loop).

**Code**:
```zig
// Automatic on Windows
const term = try sailor.term.Terminal.init();
// Polls size on Windows, uses SIGWINCH on Linux/macOS
```

## Debugging

### Enable Debug Logging

```powershell
$env:SAILOR_DEBUG = "1"
zig build run
```

**Output**:
```
[sailor:windows] ConPTY detected
[sailor:buffer] diff: 15 cells changed (12ms)
[sailor:term] raw mode enabled
```

### Check Terminal Capabilities

```zig
const term = try sailor.term.Terminal.init();
defer term.deinit();

const caps = term.getCapabilities();
std.debug.print("Truecolor: {}\n", .{caps.truecolor});
std.debug.print("Mouse: {}\n", .{caps.mouse_sgr});
std.debug.print("Clipboard: {}\n", .{caps.clipboard_osc52});
```

### Windows Terminal Version Check

```powershell
Get-AppxPackage -Name Microsoft.WindowsTerminal | Select-Object Version
```

**Minimum**: v1.12.10393.0 (for full sailor support)

## Performance

### ConPTY vs Legacy

| Operation | ConPTY (Win10 1809+) | Legacy (Win7/8) |
|-----------|----------------------|-----------------|
| Buffer.diff | 0.05ms | 0.05ms |
| ANSI emit | 0.01ms | **0.15ms** (10× slower) |
| Full render | 0.8ms | **3.5ms** (4× slower) |

**Recommendation**: Use Windows 10 1809+ with Windows Terminal for best performance.

### Optimization Tips

1. **Minimize redraws**: Use `Buffer.diff()` to only update changed cells
2. **Batch writes**: Group multiple ANSI sequences together
3. **Reduce allocations**: Use arena allocators for frame-scoped work
4. **Disable mouse tracking**: Only enable if needed (saves ~0.2ms/frame)

```zig
// Good: Batch writes
const buf = try allocator.alloc(u8, 1024);
var stream = std.io.fixedBufferStream(buf);
const writer = stream.writer();

try writer.print("\x1b[2J", .{}); // Clear
try writer.print("\x1b[H", .{});  // Home
try term.writeAll(stream.getWritten());

// Bad: Multiple small writes
try term.writeAll("\x1b[2J");
try term.writeAll("\x1b[H");
```

## Troubleshooting

### "Terminal not a TTY" Error

**Cause**: stdout is redirected to a file/pipe.

**Fix**: Check `sailor.term.isatty()` before creating Terminal:

```zig
if (!sailor.term.isatty(.stdout)) {
    // Fallback to plain text output
    return error.NotATty;
}
```

### Colors Not Showing

**Cause**: Terminal doesn't support truecolor or ANSI colors.

**Fix**: Check `COLORTERM` environment variable:

```powershell
$env:COLORTERM = "truecolor"
zig build run
```

### High CPU Usage

**Cause**: Tight event loop without sleep.

**Fix**: Use `pollEvent()` with timeout:

```zig
while (true) {
    const event = try term.pollEvent(100); // 100ms timeout
    if (event) |e| {
        // Handle event
    }
    // CPU-friendly: sleeps when no events
}
```

## Examples

See [`examples/`](../../examples/) for complete Windows-compatible demos:

- `hello.zig` — Basic TUI with colors
- `counter.zig` — Stateful widget with keyboard input
- `dashboard.zig` — Multi-widget layout

All examples work on **Windows Terminal**, **WezTerm**, and **Alacritty** without modification.

## CI/CD

sailor's CI runs native Windows tests on every commit:

```yaml
# .github/workflows/ci.yml
- os: Windows
  arch: x86_64
  runner: windows-latest
```

**Verified**:
- ✅ Windows 10 (build 1809+)
- ✅ Windows 11
- ✅ Windows Server 2022

## Further Reading

- [Windows Terminal Documentation](https://docs.microsoft.com/en-us/windows/terminal/)
- [ConPTY API](https://docs.microsoft.com/en-us/windows/console/creating-a-pseudoconsole-session)
- [ANSI Escape Sequences on Windows](https://docs.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences)
- [sailor Troubleshooting Guide](../troubleshooting.md)
