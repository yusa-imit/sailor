# sailor 🚢

> A modern Zig TUI framework & CLI toolkit with zero dependencies.

sailor is a batteries-included library for building terminal applications in Zig. From simple CLI tools with colored output to full-featured TUI applications with complex layouts and widgets — sailor has you covered.

**Key Features:**
- 🎨 **Rich CLI** - Styled output, progress bars, tables, REPL
- 🖥️ **Full TUI** - Layout system, 17+ widgets, event handling
- 🔧 **Modular** - Use only what you need, each module is independent
- 🌍 **Cross-platform** - Linux, macOS, Windows (x86_64 & ARM64)
- 🚀 **Zero dependencies** - Only the Zig standard library
- 📦 **Library-first** - No global state, bring your own allocator

## Quick Start

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var terminal = try sailor.tui.Terminal.init(gpa.allocator());
    defer terminal.deinit();

    try terminal.run(render);
}

fn render(frame: *sailor.tui.Frame) !void {
    const block = sailor.tui.widgets.Block.init()
        .setTitle(sailor.tui.Line.fromString("Hello, sailor!"))
        .setBorders(sailor.tui.Borders.all);

    const para = sailor.tui.widgets.Paragraph.init(
        sailor.tui.Line.fromString("Press Ctrl+C to exit")
    ).setBlock(block);

    frame.renderWidget(para, frame.size());
}
```

## Modules

| Module | Description | Version |
|--------|-------------|---------|
| **term** | Terminal backend (raw mode, key reading, TTY detection, size) | ✅ v0.1.0 |
| **color** | Styled output (ANSI codes, 256/truecolor, NO_COLOR support) | ✅ v0.1.0 |
| **arg** | Argument parser (flags, subcommands, auto-help) | ✅ v0.1.0 |
| **repl** | Interactive REPL (line editing, history, completion) | ✅ v0.2.0 |
| **progress** | Progress indicators (bar, spinner, multi-progress) | ✅ v0.2.0 |
| **fmt** | Result formatting (table, JSON, CSV, plain text) | ✅ v0.2.0 |
| **tui** | Full-screen TUI framework (layout, widgets, events) | ✅ v0.3.0 |

## Widgets

**Core Widgets** (v0.4.0):
Block, Paragraph, List, Table, Input, Tabs, StatusBar, Gauge

**Advanced Widgets** (v0.5.0):
Tree, TextArea, Sparkline, BarChart, LineChart, Canvas, Dialog, Popup, Notification

See the [Widget Gallery](docs/GUIDE.md#widget-gallery) for examples.

## Documentation

- **[Getting Started Guide](docs/GUIDE.md)** - Tutorials and examples
- **[API Reference](docs/API.md)** - Complete API documentation
- **[PRD](docs/PRD.md)** - Design rationale and architecture

## Installation

**Requirements:** Zig 0.15.x or later

Add to your `build.zig.zon`:

```zig
.{
    .name = "myapp",
    .version = "0.1.0",
    .paths = .{""},
    .dependencies = .{
        .sailor = .{
            .path = "../sailor",  // Local development
            // .url = "https://...",  // Or git URL when published
        },
    },
}
```

Update `build.zig`:

```zig
const sailor = b.dependency("sailor", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("sailor", sailor.module("sailor"));
```

See the [installation guide](docs/GUIDE.md#installation) for details.

## Examples

### CLI with Styled Output

```zig
const sailor = @import("sailor");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try sailor.color.ok(stdout, "✓ Build successful\n");
    try sailor.color.err(stdout, "✗ Test failed\n");
    try sailor.color.warn(stdout, "⚠ Deprecated API\n");
}
```

### Argument Parsing

```zig
var parser = sailor.arg.Parser.init(allocator);
defer parser.deinit();

parser.addFlag(.{
    .long = "output",
    .short = 'o',
    .type = .string,
    .description = "Output file path",
    .required = true,
});

const args = try parser.parse();
const output = args.flag("output").?;
```

### Progress Bar

```zig
var bar = try sailor.progress.Bar.init(allocator, 100);
defer bar.deinit();

for (0..101) |i| {
    bar.set(i);
    try bar.render(std.io.getStdOut().writer());
    std.time.sleep(20 * std.time.ns_per_ms);
}
```

### TUI Application

```zig
var terminal = try sailor.tui.Terminal.init(allocator);
defer terminal.deinit();

const app = App{ .counter = 0 };

while (app.running) {
    try terminal.draw(app, render);

    if (try terminal.pollEvent(100)) |event| {
        switch (event) {
            .key => |key| switch (key) {
                .char => |c| if (c == 'q') app.running = false,
                .ctrl_c => app.running = false,
                else => {},
            },
            else => {},
        }
    }
}
```

See [examples/](examples/) for complete applications.

## Development

```bash
# Build library
zig build

# Run tests (308+ tests)
zig build test

# Run examples
zig build example -- hello
zig build example -- counter
zig build example -- dashboard

# Cross-compile verification
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=x86_64-windows-msvc
zig build -Dtarget=aarch64-macos
```

## Platform Support

| Platform | x86_64 | ARM64 |
|----------|--------|-------|
| **Linux** | ✅ | ✅ |
| **macOS** | ✅ | ✅ |
| **Windows** | ✅ | ✅ |

All platforms are tested in CI on every commit.

## Features by Version

| Version | Features |
|---------|----------|
| **v0.1.0** | Terminal backend, styled output, argument parsing |
| **v0.2.0** | REPL, progress indicators, table formatting |
| **v0.3.0** | TUI core (layout, buffer, rendering) |
| **v0.4.0** | Core widgets (Block, List, Table, Input, Tabs, etc.) |
| **v0.5.0** | Advanced widgets (Tree, TextArea, Charts, Dialog, etc.) |
| **v1.0.0** | Polish, theming, animation, comprehensive docs |

## Design Principles

- **Library-first** - No global state, you control allocations
- **Writer-based** - All output via `std.io.Writer`, never direct stdout/stderr
- **Error-aware** - No panics in library code, explicit error handling
- **Modular** - Use `sailor.color` without importing `sailor.tui`
- **Cross-platform** - Platform differences handled internally
- **Well-tested** - 308+ tests with 100% coverage of public APIs

## Inspiration

sailor draws inspiration from:
- [ratatui](https://github.com/ratatui-org/ratatui) (Rust) - Widget architecture and layout system
- [bubbletea](https://github.com/charmbracelet/bubbletea) (Go) - Event-driven TUI model
- [colored](https://github.com/mackwic/colored) (Rust) - ANSI color API design

## Contributing

Contributions welcome! Please:
1. Read [CLAUDE.md](CLAUDE.md) for project structure
2. Run `zig build test` before submitting
3. Follow existing code style (see [docs/GUIDE.md](docs/GUIDE.md#best-practices))

## License

MIT License - see [LICENSE](LICENSE) for details.

---

Built with ❤️ in Zig. Ship your CLI/TUI apps with **sailor**! 🚢
