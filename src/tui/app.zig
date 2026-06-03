//! AppShell — high-level application entry point for multi-screen TUI apps.
//!
//! AppShell wraps a ScreenRouter and provides top-level application configuration.
//! It manages FPS capping and global exit behavior (e.g., quit on 'q' key).
//!
//! ## Design
//! - Owns a ScreenRouter and provides access via router() method
//! - Configuration through AppConfig struct
//! - No direct terminal interaction (that is caller's responsibility)
//!
//! ## Usage
//! ```zig
//! var shell = AppShell.init(allocator, .{ .fps_cap = 60, .exit_on_q = true });
//! defer shell.deinit();
//!
//! const router_ptr = shell.router();
//! // Use router_ptr to manage screens...
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const ScreenRouter = @import("router.zig").ScreenRouter;

/// Application configuration
pub const AppConfig = struct {
    /// Target frames per second (default: 60)
    fps_cap: u8 = 60,
    /// Exit application when 'q' key is pressed (default: true)
    exit_on_q: bool = true,
};

/// High-level application shell for multi-screen TUI applications
pub const AppShell = struct {
    allocator: Allocator,
    config: AppConfig,
    _router: ScreenRouter,

    /// Initialize a new AppShell with the given allocator and configuration
    pub fn init(allocator: Allocator, config: AppConfig) AppShell {
        return .{
            .allocator = allocator,
            .config = config,
            ._router = ScreenRouter.init(allocator),
        };
    }

    /// Free all resources associated with this AppShell
    pub fn deinit(self: *AppShell) void {
        self._router.deinit();
    }

    /// Get a mutable pointer to the underlying ScreenRouter
    pub fn router(self: *AppShell) *ScreenRouter {
        return &self._router;
    }
};
