//! Environment variable configuration system
//!
//! Provides standardized access to environment variables with:
//! - String retrieval with defaults (`get`)
//! - Boolean parsing with case-insensitive matching (`getBool`)
//! - Integer parsing with type bounds checking (`getInt`)

const std = @import("std");

// C library bindings for environment variable manipulation
// These are needed for tests since Zig 0.15.2's std.posix doesn't have setenv/unsetenv
extern "c" fn setenv(key: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(key: [*:0]const u8) c_int;

/// Retrieves an environment variable with a fallback default.
///
/// If the environment variable is set (even to an empty string),
/// its value is duplicated using the provided allocator and returned.
/// If the environment variable is not set, the default value is duplicated
/// instead. The caller is responsible for freeing the returned memory.
///
/// Args:
///   allocator: Memory allocator for duplicating the result
///   key: Environment variable name
///   default: Fallback value if env var is not set
///
/// Returns:
///   Allocated string containing either the env var value or the default.
///   Caller must free the returned slice.
pub fn get(allocator: std.mem.Allocator, key: []const u8, default: []const u8) ![]const u8 {
    // Try to get the env var from the environment
    const env_value = std.posix.getenv(key);

    if (env_value) |value| {
        // Environment variable is set; duplicate it
        return try allocator.dupe(u8, value);
    } else {
        // Environment variable is not set; use default
        return try allocator.dupe(u8, default);
    }
}

/// Parses an environment variable as a boolean value.
///
/// Recognizes the following as true (case-insensitive):
///   "1", "true", "yes", "on", "y"
///
/// Recognizes the following as false (case-insensitive):
///   "0", "false", "no", "off", "n"
///
/// Any other value (including empty string) is treated as false.
/// If the environment variable is not set, returns the provided default.
///
/// Args:
///   key: Environment variable name
///   default: Fallback value if env var is not set
///
/// Returns:
///   Parsed boolean value or default
pub fn getBool(key: []const u8, default: bool) bool {
    const env_value = std.posix.getenv(key) orelse return default;

    // Convert to lowercase for case-insensitive comparison
    if (env_value.len >= 32) {
        // Value too long to fit in buffer; treat as false
        return false;
    }

    var lowercase: [32]u8 = undefined;
    for (env_value, 0..) |c, i| {
        lowercase[i] = std.ascii.toLower(c);
    }

    const lower = lowercase[0..env_value.len];

    // Check for true values
    if (std.mem.eql(u8, lower, "1") or
        std.mem.eql(u8, lower, "true") or
        std.mem.eql(u8, lower, "yes") or
        std.mem.eql(u8, lower, "on") or
        std.mem.eql(u8, lower, "y")) {
        return true;
    }

    // Check for false values
    if (std.mem.eql(u8, lower, "0") or
        std.mem.eql(u8, lower, "false") or
        std.mem.eql(u8, lower, "no") or
        std.mem.eql(u8, lower, "off") or
        std.mem.eql(u8, lower, "n")) {
        return false;
    }

    // Any other value (including empty string) is treated as false
    return false;
}

/// Parses an environment variable as an integer of the specified type.
///
/// Attempts to parse the environment variable value as an integer.
/// If parsing fails (invalid format, overflow, or env var not set),
/// returns the provided default value.
///
/// The parser uses `std.fmt.parseInt` with base 10 and expects
/// strictly numeric input (leading/trailing whitespace is rejected).
///
/// Args:
///   T: The integer type to parse into (e.g., u8, u16, u32, i32, i64)
///   key: Environment variable name
///   default: Fallback value on parse error or missing env var
///
/// Returns:
///   Parsed integer or default value
pub fn getInt(comptime T: type, key: []const u8, default: T) T {
    const env_value = std.posix.getenv(key) orelse return default;

    // Try to parse as integer with base 10
    const result = std.fmt.parseInt(T, env_value, 10) catch {
        // On any parse error, return the default
        return default;
    };

    return result;
}
