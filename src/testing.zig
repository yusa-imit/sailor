//! Testing utilities for sailor
//!
//! Provides mock implementations and test helpers for writing tests
//! without requiring a real TTY or terminal.

const std = @import("std");

pub const mock_terminal = @import("testing/mock_terminal.zig");
pub const MockTerminal = mock_terminal.MockTerminal;
pub const Size = mock_terminal.Size;

pub const snapshot = @import("testing/snapshot.zig");
pub const Snapshot = snapshot.Snapshot;
pub const SnapshotRecorder = snapshot.SnapshotRecorder;

pub const property = @import("testing/property.zig");
pub const Generator = property.Generator;
pub const PropertyTest = property.PropertyTest;

test {
    // Pull in all tests from sub-modules
    std.testing.refAllDeclsRecursive(@This());
}
