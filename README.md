# sailor

Zig TUI framework & CLI toolkit. Zero dependencies beyond the Zig standard library.

Each module is independently usable — pick only what you need.

## Modules

| Module | Description |
|--------|-------------|
| `term` | Terminal backend — raw mode, key reading, TTY detection, terminal size |
| `color` | Styled output — ANSI codes, 256/truecolor, `NO_COLOR` support |
| `arg` | Argument parser — flags, subcommands, auto-generated help |
| `repl` | Interactive REPL — line editing, history, tab completion, syntax highlighting |
| `progress` | Progress indicators — bar, spinner, multi-progress |
| `fmt` | Result formatting — table, JSON, CSV, plain text |
| `tui` | Full-screen TUI framework — layout engine, double-buffered rendering, widgets |

### Widgets

Block, Paragraph, List, Table, Input, Tabs, StatusBar, Gauge — with more coming in v0.5.0.

## Requirements

- Zig 0.15.x

## Installation

Add sailor to your `build.zig.zon`:

```zig
.dependencies = .{
    .sailor = .{
        .path = "../sailor",
    },
},
```

Then in `build.zig`:

```zig
const sailor = b.dependency("sailor", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("sailor", sailor.module("sailor"));
```

## Usage

```zig
const sailor = @import("sailor");

// Parse CLI arguments
var parser = sailor.arg.Parser.init(allocator);
defer parser.deinit();
parser.addFlag(.{ .long = "verbose", .short = 'v', .description = "Enable verbose output" });
const args = try parser.parse();

// Styled output
const style = sailor.color.Style{ .fg = .green, .bold = true };
try style.write(writer, "success\n");

// Full-screen TUI
var terminal = try sailor.tui.Terminal.init(allocator);
defer terminal.deinit();
try terminal.run(struct {
    pub fn render(frame: *sailor.tui.Frame) !void {
        const area = frame.size();
        // render widgets here
        _ = area;
    }
}.render);
```

## Build

```bash
zig build          # build library
zig build test     # run all tests
```

Cross-compile check:

```bash
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-linux-gnu
zig build -Dtarget=x86_64-windows-msvc
zig build -Dtarget=aarch64-macos
```

## Platform Support

| Target | Status |
|--------|--------|
| x86_64-linux-gnu | Supported |
| aarch64-linux-gnu | Supported |
| x86_64-macos | Supported |
| aarch64-macos | Supported |
| x86_64-windows-msvc | Supported |
| aarch64-windows-msvc | Supported |

## License

MIT
