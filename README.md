# sailor

> A Zig TUI framework and CLI toolkit with zero dependencies.

sailor is a library for building terminal applications in Zig 0.16: a CLI layer (argument parsing,
styled output, REPL, progress bars, result formatters) and an immediate-mode, ratatui-style TUI
core (cell buffer, constraint layout solver, themes, input handling) with 140 widget files.

**What you get:**

- **CLI layer**: `term`, `color`, `arg` (flags, subcommands, did-you-mean), `repl` (line editor,
  history, completion), `progress` (bar, spinner), `fmt` (table, JSON, CSV, plain).
- **TUI core**: double-buffered diffing renderer, constraint layout, flexbox and grid, theming,
  sixel/kitty/iterm2 image protocols, async event loop, mouse and gamepad input.
- **140 widget files**: Block, Paragraph, List, Table, Input, TextArea, Tree, Tabs, Dialog,
  about 50 chart types, editors, file and hex browsers, kanban, gantt, DAG, timeline, pipeline.
- **Library discipline**: no global state, you inject the allocator and `std.Io`, all output
  goes through a caller-supplied `std.Io.Writer`, never straight to stdout.
- **Zero dependencies**: Zig standard library only.

## Requirements

Zig **0.16.0** (`minimum_zig_version` in `build.zig.zon`). CI runs the tests on Linux x86_64,
macOS ARM64 and Windows x86_64, and cross-compiles six targets on every pull request.

## Installation

```bash
zig fetch --save https://github.com/yusa-imit/sailor/archive/refs/tags/v3.0.0.tar.gz
```

This writes the dependency with its hash into your `build.zig.zon`. Then in `build.zig`:

```zig
const sailor = b.dependency("sailor", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("sailor", sailor.module("sailor"));
```

## Quick start

Widgets are plain structs with `render(self, buf: *Buffer, area: Rect)`. This is the core of
[`examples/hello.zig`](examples/hello.zig), which also shows how to write the buffer out:

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var buffer = try sailor.tui.Buffer.init(gpa, 40, 5);
    defer buffer.deinit();

    const area = sailor.tui.Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    var block = sailor.tui.widgets.Block{ .title = "Hello, sailor", .borders = .all };
    block.render(&buffer, area);
}
```

`main` takes `std.process.Init` because Zig 0.16 hands the binary its `gpa`, `io` and
environment there. Anything in sailor that touches the clock, the filesystem or the terminal
takes an `io: std.Io` argument, first after the receiver; libraries never construct one.

## Modules

| Module | Description |
|--------|-------------|
| `term` | Raw mode, key reading, TTY detection, terminal size (POSIX and Windows backends) |
| `color` | ANSI 16/256/truecolor styling, `NO_COLOR` support |
| `arg` | Flag and subcommand parser, generated help, did-you-mean suggestions |
| `repl` | Line editor, history, completion, multi-line validation |
| `progress` | Progress bar, spinner, multi-progress |
| `fmt` | Table, JSON, CSV and plain-text result formatters |
| `tui` | Buffer, layout solver, style, theming, widgets, event loop |

Modules are layered `term → color → arg → repl → progress → fmt → tui`; lower layers never
import higher ones, so `sailor.color` can be used without pulling in `sailor.tui`.

## Documentation

- [Getting started](docs/getting-started.md) and [guide](docs/GUIDE.md)
- [API reference](docs/API.md), including the before/after table for the v3.0.0 `io` changes
- [Product requirements and design](docs/PRD.md)
- [Changelog](CHANGELOG.md)
- Runnable programs in [`examples/`](examples/)

## Development

```bash
zig build              # library and CLI
zig build test         # unit tests (about 13.9k) plus the tidy check
zig fmt --check src build.zig
zig build example-hello
```

The `tidy` step enforces the Tiger Style limits (line and function length, `//!` headers,
no unproven `catch unreachable`) against the ratchet in `tidy_baseline.txt`, which may only
shrink.

## Platform support

| Platform | x86_64 | ARM64 |
|----------|--------|-------|
| Linux | cross-compiled in CI; tests run on x86_64 | cross-compiled in CI |
| macOS | cross-compiled in CI | tests run in CI |
| Windows | tests run in CI | cross-compiled in CI |

## Design principles

- **Immediate mode**: no persistent widget tree; every frame builds, renders and diffs.
- **Writer-based output**: everything goes through a caller-supplied `std.Io.Writer`.
- **Typed errors for user data**: malformed input and failed I/O are returned, not asserted;
  caller contract violations are asserted (Tiger Style).
- **Explicit allocation**: callers pass the allocator; limits are visible in signatures.
- **Modular**: use only the layers you need.

## Inspiration

- [ratatui](https://github.com/ratatui-org/ratatui) (Rust): widget architecture and layout
- [bubbletea](https://github.com/charmbracelet/bubbletea) (Go): event-driven TUI model

## Contributing

Run `zig build test` and `zig fmt --check src build.zig` before opening a pull request, and
follow the existing code style.

## License

MIT, see [LICENSE](LICENSE).
