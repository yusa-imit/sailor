const std = @import("std");

/// Render budget tracker for maintaining target frame rate.
/// Tracks frame render times and provides skip/throttle signals when overdue.
pub const RenderBudget = struct {
    /// Target frame time in nanoseconds (e.g., 16_666_667 for 60fps)
    target_frame_ns: u64,
    /// Last frame start timestamp
    last_frame_ns: u64,
    /// Accumulated debt from slow frames (in nanoseconds)
    debt_ns: u64,
    /// Maximum debt before forcing frame skip (default: 2x target_frame_ns)
    max_debt_ns: u64,
    /// Statistics
    stats: Stats,

    pub const Stats = struct {
        total_frames: u64 = 0,
        skipped_frames: u64 = 0,
        min_frame_ns: u64 = std.math.maxInt(u64),
        max_frame_ns: u64 = 0,
        avg_frame_ns: u64 = 0,
        _sum_ns: u64 = 0,

        pub fn recordFrame(self: *Stats, frame_time_ns: u64) void {
            self.total_frames += 1;
            self._sum_ns += frame_time_ns;
            self.avg_frame_ns = self._sum_ns / self.total_frames;
            self.min_frame_ns = @min(self.min_frame_ns, frame_time_ns);
            self.max_frame_ns = @max(self.max_frame_ns, frame_time_ns);
        }

        pub fn recordSkip(self: *Stats) void {
            self.skipped_frames += 1;
        }

        pub fn fps(self: Stats) f64 {
            if (self.avg_frame_ns == 0) return 0.0;
            return 1_000_000_000.0 / @as(f64, @floatFromInt(self.avg_frame_ns));
        }
    };

    /// Initialize with target FPS (default: 60)
    pub fn init(target_fps: u32) RenderBudget {
        const target_ns = 1_000_000_000 / @as(u64, target_fps);
        return .{
            .target_frame_ns = target_ns,
            .last_frame_ns = 0,
            .debt_ns = 0,
            .max_debt_ns = target_ns * 2, // 2 frames of debt before skip
            .stats = .{},
        };
    }

    /// Start a new frame. Returns true if frame should be rendered, false if should skip.
    pub fn startFrame(self: *RenderBudget) bool {
        const now = std.time.nanoTimestamp();

        if (self.last_frame_ns == 0) {
            // First frame, always render
            self.last_frame_ns = @intCast(now);
            return true;
        }

        const elapsed = @as(u64, @intCast(now)) - self.last_frame_ns;

        // Check if we're behind schedule
        if (elapsed < self.target_frame_ns) {
            // Ahead of schedule, no render needed yet
            return false;
        }

        // Calculate debt from this frame
        const overage = elapsed -| self.target_frame_ns;
        self.debt_ns += overage;

        // If debt exceeds threshold, skip this frame to catch up
        if (self.debt_ns > self.max_debt_ns) {
            self.stats.recordSkip();
            self.last_frame_ns = @intCast(now);
            // Reduce debt by target frame time (we skipped a frame)
            self.debt_ns = self.debt_ns -| self.target_frame_ns;
            return false;
        }

        self.last_frame_ns = @intCast(now);
        return true;
    }

    /// End current frame, record stats
    pub fn endFrame(self: *RenderBudget) void {
        const now = std.time.nanoTimestamp();
        const frame_time = @as(u64, @intCast(now)) - self.last_frame_ns;
        self.stats.recordFrame(frame_time);

        // Pay down debt if we were fast
        if (frame_time < self.target_frame_ns) {
            const surplus = self.target_frame_ns - frame_time;
            self.debt_ns = self.debt_ns -| surplus;
        }
    }

    /// Check if currently over budget (useful for conditional rendering)
    pub fn isOverBudget(self: RenderBudget) bool {
        return self.debt_ns > 0;
    }

    /// Get remaining budget for current frame in nanoseconds
    pub fn remainingBudget(self: RenderBudget) u64 {
        if (self.last_frame_ns == 0) return self.target_frame_ns;

        const now = std.time.nanoTimestamp();
        const elapsed = @as(u64, @intCast(now)) - self.last_frame_ns;

        if (elapsed >= self.target_frame_ns) return 0;
        return self.target_frame_ns - elapsed;
    }

    /// Reset statistics
    pub fn resetStats(self: *RenderBudget) void {
        self.stats = .{};
        self.debt_ns = 0;
    }
};

test "RenderBudget init" {
    const budget = RenderBudget.init(60);
    try std.testing.expectEqual(@as(u64, 16_666_666), budget.target_frame_ns);
    try std.testing.expectEqual(@as(u64, 0), budget.debt_ns);
    try std.testing.expectEqual(@as(u64, 33_333_332), budget.max_debt_ns);
}

test "RenderBudget first frame always renders" {
    var budget = RenderBudget.init(60);
    try std.testing.expect(budget.startFrame());
}

test "RenderBudget stats record frame" {
    var stats = RenderBudget.Stats{};
    stats.recordFrame(10_000_000); // 10ms
    stats.recordFrame(20_000_000); // 20ms

    try std.testing.expectEqual(@as(u64, 2), stats.total_frames);
    try std.testing.expectEqual(@as(u64, 15_000_000), stats.avg_frame_ns);
    try std.testing.expectEqual(@as(u64, 10_000_000), stats.min_frame_ns);
    try std.testing.expectEqual(@as(u64, 20_000_000), stats.max_frame_ns);
}

test "RenderBudget stats fps calculation" {
    var stats = RenderBudget.Stats{};
    stats.recordFrame(16_666_666); // ~60fps

    const calculated_fps = stats.fps();
    try std.testing.expect(calculated_fps > 59.9);
    try std.testing.expect(calculated_fps < 60.1);
}

test "RenderBudget stats record skip" {
    var stats = RenderBudget.Stats{};
    stats.recordSkip();
    stats.recordSkip();

    try std.testing.expectEqual(@as(u64, 2), stats.skipped_frames);
}

test "RenderBudget isOverBudget" {
    var budget = RenderBudget.init(60);
    try std.testing.expect(!budget.isOverBudget());

    budget.debt_ns = 1000;
    try std.testing.expect(budget.isOverBudget());
}

test "RenderBudget resetStats" {
    var budget = RenderBudget.init(60);
    budget.debt_ns = 5000;
    budget.stats.total_frames = 10;
    budget.stats.skipped_frames = 2;

    budget.resetStats();

    try std.testing.expectEqual(@as(u64, 0), budget.debt_ns);
    try std.testing.expectEqual(@as(u64, 0), budget.stats.total_frames);
    try std.testing.expectEqual(@as(u64, 0), budget.stats.skipped_frames);
}
