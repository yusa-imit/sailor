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
pub const tui = @import("tui/tui.zig");

// Phase 6 modules (v1.0.0)
pub const bench = @import("bench.zig");

// Post-v1.0 modules (v1.1.0 — Accessibility & Internationalization)
pub const accessibility = @import("accessibility.zig");
pub const focus = @import("focus.zig");
pub const keybindings = @import("keybindings.zig");
pub const unicode = @import("unicode.zig");
pub const bidi = @import("bidi.zig");

// v1.4.0 — Memory Management
pub const pool = @import("pool.zig");

// v1.5.0 — State Management & Testing
pub const eventbus = @import("eventbus.zig");
pub const command = @import("command.zig");

// v1.14.0 — Performance & Memory Optimization
pub const profiler = @import("profiler.zig");

// Convenient re-exports from tui submodules
pub const Buffer = tui.buffer.Buffer;
pub const Cell = tui.buffer.Cell;
pub const Rect = tui.layout.Rect;
pub const Style = tui.style.Style;
pub const Viewport = tui.viewport.Viewport;
pub const VirtualRenderer = tui.virtual.VirtualRenderer;
pub const IncrementalLayout = tui.incremental_layout.IncrementalLayout;
pub const LayoutCache = tui.layout_cache.LayoutCache;
pub const CompressedBuffer = tui.buffer_compression.CompressedBuffer;

test {
    // Pull in all module tests
    std.testing.refAllDecls(@This());
}
