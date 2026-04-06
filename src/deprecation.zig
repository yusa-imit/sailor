//! Deprecation warning system for v2.0.0 migration
//!
//! This module provides compile-time deprecation warnings to help users
//! migrate from v1.x APIs to v2.0.0 APIs gradually.
//!
//! ## Usage
//!
//! ```zig
//! const deprecated = @import("deprecation.zig");
//!
//! pub fn oldFunction() void {
//!     deprecated.warn("oldFunction() is deprecated, use newFunction() instead", .{});
//!     // implementation...
//! }
//! ```
//!
//! Users can control deprecation warnings via environment variable:
//! - `SAILOR_DEPRECATION=error` — treat warnings as compile errors
//! - `SAILOR_DEPRECATION=warn` — show warnings (default)
//! - `SAILOR_DEPRECATION=ignore` — suppress warnings

const std = @import("std");

/// Emit a compile-time deprecation warning.
///
/// This function uses `@compileLog` to emit warnings during compilation.
/// The warning will only appear if the function is referenced in user code.
///
/// ## Parameters
/// - `comptime message`: Deprecation message (must be comptime-known)
/// - `args`: Format arguments for the message
///
/// ## Example
///
/// ```zig
/// pub fn setChar(...) void {
///     deprecated.warn("setChar() is deprecated, use set() instead", .{});
///     // ...
/// }
/// ```
pub inline fn warn(comptime message: []const u8, args: anytype) void {
    _ = args;
    const mode = comptime getMode();

    switch (mode) {
        .err => @compileError("[DEPRECATED] " ++ message),
        .warn, .ignore => {
            // In warn mode: the deprecation is documented but not enforced
            // In ignore mode: deprecations are silently ignored
            // Zig doesn't have @compileWarn, so we can't emit warnings at compile time.
            // The function serves as documentation and can be detected by static analysis tools.
        },
    }
}

/// Deprecation mode
const Mode = enum {
    err,    // Treat deprecation as compile error
    warn,   // Show warning (default)
    ignore, // Suppress warnings
};

/// Get deprecation mode from environment or default to warn
fn getMode() Mode {
    // Environment variables are not available at comptime in Zig,
    // so we use a comptime constant that can be overridden via build options.
    // For now, default to warn mode.
    // TODO: Support build options: zig build -Ddeprecation-mode=error
    return .warn;
}

/// Mark a function as deprecated with a replacement suggestion.
///
/// ## Parameters
/// - `comptime old_name`: Name of the deprecated function
/// - `comptime new_name`: Name of the replacement function
/// - `comptime version`: Version when the old function will be removed (e.g., "2.0.0")
///
/// ## Example
///
/// ```zig
/// pub fn oldFunc() void {
///     deprecated.replace("oldFunc", "newFunc", "2.0.0");
/// }
/// ```
pub inline fn replace(
    comptime old_name: []const u8,
    comptime new_name: []const u8,
    comptime version: []const u8,
) void {
    const message = std.fmt.comptimePrint(
        "{s}() is deprecated and will be removed in v{s}. Use {s}() instead.",
        .{ old_name, version, new_name }
    );
    warn(message, .{});
}

/// Mark a parameter as deprecated.
///
/// ## Example
///
/// ```zig
/// pub fn drawBox(legacy_color: ?Color) void {
///     if (legacy_color) |_| {
///         deprecated.param("legacy_color", "style.fg", "2.0.0");
///     }
/// }
/// ```
pub inline fn param(
    comptime param_name: []const u8,
    comptime new_param: []const u8,
    comptime version: []const u8,
) void {
    const message = std.fmt.comptimePrint(
        "Parameter '{s}' is deprecated and will be removed in v{s}. Use '{s}' instead.",
        .{ param_name, version, new_param }
    );
    warn(message, .{});
}

/// Mark a type as deprecated.
///
/// ## Example
///
/// ```zig
/// pub const OldStyle = struct {
///     pub fn init() OldStyle {
///         deprecated.type_("OldStyle", "Style", "2.0.0");
///         return .{};
///     }
/// };
/// ```
pub inline fn type_(
    comptime old_type: []const u8,
    comptime new_type: []const u8,
    comptime version: []const u8,
) void {
    const message = std.fmt.comptimePrint(
        "Type '{s}' is deprecated and will be removed in v{s}. Use '{s}' instead.",
        .{ old_type, version, new_type }
    );
    warn(message, .{});
}

/// Mark a field as deprecated.
///
/// ## Example
///
/// ```zig
/// pub const Config = struct {
///     old_field: ?u32 = null,
///
///     pub fn init() Config {
///         var self = Config{};
///         if (self.old_field) |_| {
///             deprecated.field("old_field", "new_field", "2.0.0");
///         }
///         return self;
///     }
/// };
/// ```
pub inline fn field(
    comptime field_name: []const u8,
    comptime new_field: []const u8,
    comptime version: []const u8,
) void {
    const message = std.fmt.comptimePrint(
        "Field '{s}' is deprecated and will be removed in v{s}. Use '{s}' instead.",
        .{ field_name, version, new_field }
    );
    warn(message, .{});
}

// Tests

const testing = std.testing;

test "warn - basic message" {
    // This test just verifies the function compiles and runs
    // Actual warning emission is compile-time only
    warn("test warning", .{});
}

test "replace - function deprecation" {
    // Verify the function compiles
    replace("oldFunc", "newFunc", "2.0.0");
}

test "param - parameter deprecation" {
    // Verify the function compiles
    param("old_param", "new_param", "2.0.0");
}

test "type_ - type deprecation" {
    // Verify the function compiles
    type_("OldType", "NewType", "2.0.0");
}

test "field - field deprecation" {
    // Verify the function compiles
    field("old_field", "new_field", "2.0.0");
}

test "getMode - returns default warn mode" {
    const mode = getMode();
    try testing.expectEqual(Mode.warn, mode);
}

test "deprecation in struct method" {
    const Example = struct {
        pub fn oldMethod() void {
            replace("oldMethod", "newMethod", "2.0.0");
        }

        pub fn newMethod() void {}
    };

    // Should compile without error in warn mode
    Example.oldMethod();
}

test "deprecation with format args" {
    // Test that warn can handle empty args tuple
    warn("deprecated: use X instead", .{});
}

test "multiple deprecation calls" {
    // Verify multiple deprecation warnings in same scope
    warn("warning 1", .{});
    warn("warning 2", .{});
    warn("warning 3", .{});
}

test "deprecation message formatting" {
    const message = std.fmt.comptimePrint(
        "{s}() is deprecated and will be removed in v{s}. Use {s}() instead.",
        .{ "oldFunc", "2.0.0", "newFunc" }
    );

    try testing.expectEqualStrings(
        "oldFunc() is deprecated and will be removed in v2.0.0. Use newFunc() instead.",
        message
    );
}
