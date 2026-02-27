//! sailor — Zig TUI framework & CLI toolkit
//!
//! Composable modules for building interactive terminal applications.
//! Each module is independently usable.
//!
//! ## Modules
//!
//! - `term`     — Terminal backend (raw mode, key reading, TTY detection)
//! - `color`    — Styled output (ANSI codes, 256/truecolor, NO_COLOR)
//! - `arg`      — Argument parser (flags, subcommands, help generation)
//! - `repl`     — Interactive REPL (line editing, history, completion)
//! - `progress` — Progress indicators (bar, spinner, multi-progress)
//! - `fmt`      — Result formatting (table, JSON, CSV)
//! - `tui`      — Full-screen TUI framework (layout, widgets, double buffering)

const std = @import("std");

// Phase 1 modules (v0.1.0)
pub const term = @import("term.zig");
pub const color = @import("color.zig");
pub const arg = @import("arg.zig");

// Phase 2 modules (v0.2.0)
pub const repl = @import("repl.zig");
pub const progress = @import("progress.zig");
pub const fmt = @import("fmt.zig");

// Phase 3+ modules (v0.3.0+)
// pub const tui = @import("tui/tui.zig");

test {
    // Pull in all module tests
    std.testing.refAllDecls(@This());
}
