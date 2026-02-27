//! TUI Framework Core Module
//!
//! Full-screen terminal user interface framework with:
//! - Double-buffered rendering
//! - Constraint-based layout system
//! - Composable widget architecture
//! - Event handling (keyboard, mouse, resize)

pub const style = @import("style.zig");

// Export style types for convenience
pub const Color = style.Color;
pub const Style = style.Style;
pub const Span = style.Span;
pub const Line = style.Line;

// TODO: Phase 3 modules (to be implemented)
// pub const buffer = @import("buffer.zig");
// pub const layout = @import("layout.zig");
// pub const symbols = @import("symbols.zig");
// pub const Terminal = @import("terminal.zig").Terminal;
// pub const Frame = @import("terminal.zig").Frame;

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
