//! Error Handling Demo — Demonstrates error recovery patterns with sailor
//!
//! Shows:
//! - Structured error reporting with error_context
//! - Debug logging with debug_log
//! - Stack trace helpers with stack_trace
//! - Error recovery strategies
//!
//! Build and run:
//! ```
//! zig build example -- error_handling
//! ```
//!
//! Enable debug logging:
//! ```
//! SAILOR_DEBUG=1 zig build example -- error_handling
//! SAILOR_DEBUG=sailor:trace zig build example -- error_handling
//! ```

const std = @import("std");
const sailor = @import("sailor");

// ============================================================================
// Example 1: Structured Error Context
// ============================================================================

fn processFileWithContext(allocator: std.mem.Allocator, path: []const u8) !void {
    const log = sailor.debug_log.scoped(.sailor);
    log.info("Processing file: {s}", .{path});

    // Create error context
    var ctx = sailor.error_context.ErrorContext.init(allocator, "error_handling_demo.zig", 36, "processing file");
    defer ctx.deinit();

    try ctx.set("path", path);

    // Simulate file processing
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        try ctx.set("error", @errorName(err));

        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(allocator);
        try ctx.format(buf.writer(allocator), err);

        std.debug.print("\nError occurred:\n{s}\n", .{buf.items});
        return err;
    };
    defer file.close();

    log.info("File opened successfully", .{});
}

// ============================================================================
// Example 2: Debug Logging
// ============================================================================

fn demonstrateDebugLogging() void {
    const log = sailor.debug_log.scoped(.sailor);

    log.trace("TRACE level message (most verbose)", .{});
    log.debug("DEBUG level message", .{});
    log.info("INFO level message", .{});
    log.warn("WARN level message", .{});
    log.err("ERROR level message (highest severity)", .{});

    // With formatting
    const count: usize = 42;
    log.info("Processed {d} items", .{count});

    const status = "complete";
    log.info("Status: {s}", .{status});
}

// ============================================================================
// Example 3: Stack Trace Helpers
// ============================================================================

fn demonstrateStackTraceHelpers() void {
    const log = sailor.debug_log.scoped(.sailor);

    // Assert with context
    const x: i32 = 10;
    sailor.stack_trace.assert(x > 0, "x must be positive, got {d}", .{x});
    log.info("Assert passed: x = {d}", .{x});

    // Require (precondition)
    const buffer_size: usize = 1024;
    sailor.stack_trace.require(buffer_size >= 256, "buffer too small: {d} bytes", .{buffer_size});
    log.info("Precondition passed: buffer_size = {d}", .{buffer_size});

    // Ensure (postcondition)
    const result: []const u8 = "success";
    sailor.stack_trace.ensure(result.len > 0, "result should not be empty", .{});
    log.info("Postcondition passed: result = '{s}'", .{result});

    // Debug helpers
    sailor.stack_trace.debugHere("checkpoint reached");
    sailor.stack_trace.debugValue("x", x);
    sailor.stack_trace.debugValue("result", result);
}

// ============================================================================
// Example 4: Error Recovery Strategies
// ============================================================================

const RecoveryStrategy = enum {
    retry,
    fallback,
    fail_fast,
};

fn processWithRetry(allocator: std.mem.Allocator, path: []const u8, max_retries: usize) !void {
    const log = sailor.debug_log.scoped(.sailor);

    var attempt: usize = 0;
    while (attempt < max_retries) : (attempt += 1) {
        log.info("Attempt {d}/{d} to process: {s}", .{ attempt + 1, max_retries, path });

        processFileWithContext(allocator, path) catch |err| {
            if (attempt + 1 >= max_retries) {
                log.err("All retries exhausted: {s}", .{@errorName(err)});
                return err;
            }

            log.warn("Retry {d} failed: {s}, retrying...", .{ attempt + 1, @errorName(err) });
            std.time.sleep(100 * std.time.ns_per_ms); // 100ms delay
            continue;
        };

        log.info("Success on attempt {d}", .{attempt + 1});
        return;
    }
}

fn processWithFallback(allocator: std.mem.Allocator, primary_path: []const u8, fallback_path: []const u8) !void {
    const log = sailor.debug_log.scoped(.sailor);

    log.info("Trying primary path: {s}", .{primary_path});
    processFileWithContext(allocator, primary_path) catch |err| {
        log.warn("Primary failed: {s}, trying fallback: {s}", .{ @errorName(err), fallback_path });

        processFileWithContext(allocator, fallback_path) catch |fallback_err| {
            log.err("Fallback also failed: {s}", .{@errorName(fallback_err)});
            return fallback_err;
        };

        log.info("Fallback succeeded", .{});
        return;
    };

    log.info("Primary succeeded", .{});
}

// ============================================================================
// Main
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Sailor Error Handling Demo ===\n\n", .{});

    // Example 1: Structured Error Context
    std.debug.print("--- Example 1: Structured Error Context ---\n", .{});
    processFileWithContext(allocator, "/nonexistent/file.txt") catch |err| {
        std.debug.print("Recovered from error: {s}\n\n", .{@errorName(err)});
    };

    // Example 2: Debug Logging
    std.debug.print("--- Example 2: Debug Logging ---\n", .{});
    std.debug.print("(Set SAILOR_DEBUG=1 to see log output)\n", .{});
    demonstrateDebugLogging();
    std.debug.print("\n", .{});

    // Example 3: Stack Trace Helpers
    std.debug.print("--- Example 3: Stack Trace Helpers ---\n", .{});
    demonstrateStackTraceHelpers();
    std.debug.print("\n", .{});

    // Example 4: Error Recovery Strategies
    std.debug.print("--- Example 4: Retry Strategy ---\n", .{});
    processWithRetry(allocator, "/nonexistent/file.txt", 3) catch |err| {
        std.debug.print("Final error after retries: {s}\n\n", .{@errorName(err)});
    };

    std.debug.print("--- Example 5: Fallback Strategy ---\n", .{});
    processWithFallback(allocator, "/nonexistent/primary.txt", "/nonexistent/fallback.txt") catch |err| {
        std.debug.print("Final error after fallback: {s}\n\n", .{@errorName(err)});
    };

    std.debug.print("=== Demo Complete ===\n", .{});
}
