//! Testing utilities for sailor
//!
//! Provides mock implementations and test helpers for writing tests
//! without requiring a real TTY or terminal.

const std = @import("std");

pub const mock_terminal = @import("testing/mock_terminal.zig");
pub const MockTerminal = mock_terminal.MockTerminal;
pub const Size = mock_terminal.Size;

test {
    // Pull in all tests from sub-modules
    std.testing.refAllDeclsRecursive(@This());
}
