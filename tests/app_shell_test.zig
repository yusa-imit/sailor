//! AppShell Tests — v2.21.0
//!
//! Tests AppShell struct initialization, configuration, and router integration.
//! AppShell manages the application lifecycle, FPS cap, and exit behavior.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const AppShell = sailor.AppShell;
const AppConfig = sailor.AppConfig;
const ScreenRouter = sailor.ScreenRouter;

// ============================================================================
// AppConfig Default Values
// ============================================================================

test "AppConfig default fps_cap is 60" {
    const config = AppConfig{};
    try testing.expectEqual(@as(u8, 60), config.fps_cap);
}

test "AppConfig default exit_on_q is true" {
    const config = AppConfig{};
    try testing.expect(config.exit_on_q);
}

// ============================================================================
// AppShell Initialization
// ============================================================================

test "AppShell init with default config creates instance" {
    const config = AppConfig{};
    var shell = AppShell.init(testing.allocator, config);
    defer shell.deinit();

    // Should not crash
}

test "AppShell router returns non-null pointer" {
    const config = AppConfig{};
    var shell = AppShell.init(testing.allocator, config);
    defer shell.deinit();

    const router_ptr = shell.router();
    // router() returns *ScreenRouter (non-optional); verify address is non-zero
    try testing.expect(@intFromPtr(router_ptr) != 0);
}

test "AppShell router returns working ScreenRouter" {
    const config = AppConfig{};
    var shell = AppShell.init(testing.allocator, config);
    defer shell.deinit();

    const router_ptr = shell.router();
    try testing.expect(!router_ptr.isRunning());
}

test "AppShell deinit is safe on empty router" {
    const config = AppConfig{};
    var shell = AppShell.init(testing.allocator, config);
    shell.deinit();

    // Should not crash
}

test "AppShell with custom fps_cap stores value" {
    const config = AppConfig{ .fps_cap = 120 };
    var shell = AppShell.init(testing.allocator, config);
    defer shell.deinit();

    try testing.expectEqual(@as(u8, 120), shell.config.fps_cap);
}

test "AppShell with exit_on_q false stores value" {
    const config = AppConfig{ .exit_on_q = false };
    var shell = AppShell.init(testing.allocator, config);
    defer shell.deinit();

    try testing.expect(!shell.config.exit_on_q);
}

test "AppShell init with custom config has correct fps_cap" {
    const config = AppConfig{ .fps_cap = 30 };
    var shell = AppShell.init(testing.allocator, config);
    defer shell.deinit();

    try testing.expectEqual(@as(u8, 30), shell.config.fps_cap);
}

test "AppShell init with custom config has correct exit_on_q" {
    const config = AppConfig{ .exit_on_q = false };
    var shell = AppShell.init(testing.allocator, config);
    defer shell.deinit();

    try testing.expect(!shell.config.exit_on_q);
}

test "AppShell init allocates from provided allocator" {
    const allocator = testing.allocator;
    const config = AppConfig{};
    var shell = AppShell.init(allocator, config);
    defer shell.deinit();

    // Should not crash — allocator was used
}

test "Two AppShells are independent" {
    const config1 = AppConfig{ .fps_cap = 60 };
    const config2 = AppConfig{ .fps_cap = 120 };

    var shell1 = AppShell.init(testing.allocator, config1);
    defer shell1.deinit();

    var shell2 = AppShell.init(testing.allocator, config2);
    defer shell2.deinit();

    try testing.expectEqual(@as(u8, 60), shell1.config.fps_cap);
    try testing.expectEqual(@as(u8, 120), shell2.config.fps_cap);
}
