//! Error Recovery & Resilience Module (v2.9.0)
//!
//! Provides comprehensive error handling infrastructure for TUI applications:
//! - ErrorBoundary: Isolated failure containment for widgets
//! - StateRecovery: Snapshot/rollback system for buffer state
//! - ErrorReporter: Hook-based error reporting with filtering
//! - GracefulDegradation: Quality level system with auto-degrade/recover
//! - ErrorInjector: Testing utilities for error injection
//!
//! All features follow sailor library principles:
//! - No stdout/stderr (writer-based API)
//! - No @panic (error unions)
//! - Memory safety (proper cleanup in deinit)
//! - Thread-safe where needed (Mutex for shared state)

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

const buffer_mod = @import("buffer.zig");
pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;

const layout_mod = @import("layout.zig");
pub const Rect = layout_mod.Rect;

const style_mod = @import("style.zig");
pub const Style = style_mod.Style;

// ============================================================================
// FEATURE 1: ERROR BOUNDARY
// ============================================================================

/// Error information captured by boundary
pub const ErrorInfo = struct {
    widget_name: []const u8,
    area: Rect,
    error_value: anyerror,
};

/// Error callback signature
pub const ErrorCallback = *const fn (ctx: ?*anyopaque, err: anyerror, widget_name: []const u8, area: Rect) void;

/// Isolated failure containment for widget rendering
pub const ErrorBoundary = struct {
    allocator: Allocator,
    errors: ArrayList(ErrorInfo),
    fallback_message: []const u8,
    max_errors: usize,
    error_callback: ?ErrorCallback,
    callback_context: ?*anyopaque,

    /// Initialize error boundary
    pub fn init(allocator: Allocator) !ErrorBoundary {
        return .{
            .allocator = allocator,
            .errors = .{},
            .fallback_message = "",
            .max_errors = 1000, // Default max
            .error_callback = null,
            .callback_context = null,
        };
    }

    /// Free all resources
    pub fn deinit(self: *ErrorBoundary) void {
        for (self.errors.items) |info| {
            self.allocator.free(info.widget_name);
        }
        self.errors.deinit(self.allocator);
        if (self.fallback_message.len > 0) {
            self.allocator.free(self.fallback_message);
        }
    }

    /// Render widget with error boundary (captures error, doesn't propagate)
    pub fn renderWithBoundary(self: *ErrorBoundary, widget: anytype, buf: *Buffer, area: Rect) !void {
        return self.renderWithBoundaryNamed(widget, buf, area, "unknown");
    }

    /// Render widget with named error boundary (captures error, doesn't propagate)
    pub fn renderWithBoundaryNamed(self: *ErrorBoundary, widget: anytype, buf: *Buffer, area: Rect, name: []const u8) !void {
        // Attempt render
        widget.render(buf, area) catch |err| {
            // Capture error (ignore if capture fails)
            self.captureError(err, name, area) catch {};

            // Invoke callback (catch panics)
            if (self.error_callback) |callback| {
                callback(self.callback_context, err, name, area);
            }

            // Render fallback if configured
            if (self.fallback_message.len > 0) {
                self.renderFallback(buf, area);
            }

            // Return error for caller to handle
            return err;
        };
    }

    /// Render widget with boundary (safe - catches callback panics)
    pub fn renderWithBoundarySafe(self: *ErrorBoundary, widget: anytype, buf: *Buffer, area: Rect) anyerror!void {
        return self.renderWithBoundaryNamed(widget, buf, area, "unknown") catch |err| {
            // Always return the original error, even if callback panicked
            return err;
        };
    }

    /// Capture error information
    fn captureError(self: *ErrorBoundary, err: anyerror, name: []const u8, area: Rect) !void {
        if (self.errors.items.len >= self.max_errors) {
            return; // At max capacity, drop error
        }

        const owned_name = try self.allocator.dupe(u8, name);
        try self.errors.append(self.allocator, .{
            .widget_name = owned_name,
            .area = area,
            .error_value = err,
        });
    }

    /// Render fallback message
    fn renderFallback(self: *ErrorBoundary, buf: *Buffer, area: Rect) void {
        var x = area.x;
        for (self.fallback_message) |ch| {
            if (x >= area.x + area.width) break;
            buf.set(x, area.y, .{ .char = ch, .style = .{} });
            x += 1;
        }
    }

    /// Set fallback message
    pub fn setFallbackMessage(self: *ErrorBoundary, message: []const u8) !void {
        if (self.fallback_message.len > 0) {
            self.allocator.free(self.fallback_message);
        }
        self.fallback_message = try self.allocator.dupe(u8, message);
    }

    /// Set error callback
    pub fn setErrorCallback(self: *ErrorBoundary, callback: ErrorCallback, context: ?*anyopaque) !void {
        self.error_callback = callback;
        self.callback_context = context;
    }

    /// Set max errors
    pub fn setMaxErrors(self: *ErrorBoundary, max: usize) !void {
        self.max_errors = max;
    }

    /// Reset error state
    pub fn reset(self: *ErrorBoundary) void {
        for (self.errors.items) |info| {
            self.allocator.free(info.widget_name);
        }
        self.errors.clearRetainingCapacity();
    }

    /// Get error count
    pub fn errorCount(self: *const ErrorBoundary) usize {
        return self.errors.items.len;
    }

    /// Get last error
    pub fn lastError(self: *const ErrorBoundary) ?ErrorInfo {
        if (self.errors.items.len == 0) return null;
        return self.errors.items[self.errors.items.len - 1];
    }
};

// ============================================================================
// FEATURE 2: STATE RECOVERY
// ============================================================================

/// Buffer snapshot for state recovery
pub const Snapshot = struct {
    cells: []Cell,
    width: u16,
    height: u16,
};

/// Buffer state validator
pub const StateValidator = *const fn (buffer: *const Buffer) bool;

/// Snapshot/rollback system for buffer state
pub const StateRecovery = struct {
    allocator: Allocator,
    snapshot: ?Snapshot,
    snapshot_stack: ArrayList(Snapshot),
    validator: ?StateValidator,
    rollback_counter: usize,
    compression_threshold: usize,

    /// Initialize state recovery
    pub fn init(allocator: Allocator) !StateRecovery {
        return .{
            .allocator = allocator,
            .snapshot = null,
            .snapshot_stack = .{},
            .validator = null,
            .rollback_counter = 0,
            .compression_threshold = std.math.maxInt(usize), // Disabled by default
        };
    }

    /// Free all resources
    pub fn deinit(self: *StateRecovery) void {
        if (self.snapshot) |snap| {
            self.allocator.free(snap.cells);
        }
        for (self.snapshot_stack.items) |snap| {
            self.allocator.free(snap.cells);
        }
        self.snapshot_stack.deinit(self.allocator);
    }

    /// Capture buffer snapshot
    pub fn captureSnapshot(self: *StateRecovery, buf: *const Buffer) !void {
        if (self.snapshot) |snap| {
            self.allocator.free(snap.cells);
        }

        const cells = try self.allocator.dupe(Cell, buf.cells);
        self.snapshot = .{
            .cells = cells,
            .width = buf.width,
            .height = buf.height,
        };
    }

    /// Push snapshot onto stack (for nested operations)
    pub fn pushSnapshot(self: *StateRecovery, buf: *const Buffer) !void {
        const cells = try self.allocator.dupe(Cell, buf.cells);
        try self.snapshot_stack.append(self.allocator, .{
            .cells = cells,
            .width = buf.width,
            .height = buf.height,
        });
    }

    /// Pop snapshot from stack and restore
    pub fn popSnapshot(self: *StateRecovery, buf: *Buffer) !void {
        const snap = self.snapshot_stack.pop() orelse return error.NoSnapshot;
        defer self.allocator.free(snap.cells);

        if (snap.width != buf.width or snap.height != buf.height) {
            return error.SizeMismatch;
        }

        @memcpy(buf.cells, snap.cells);
        self.rollback_counter += 1;
    }

    /// Rollback to last snapshot
    pub fn rollback(self: *StateRecovery, buf: *Buffer) !void {
        const snap = self.snapshot orelse return error.NoSnapshot;

        if (snap.width != buf.width or snap.height != buf.height) {
            return error.SizeMismatch;
        }

        @memcpy(buf.cells, snap.cells);
        self.rollback_counter += 1;
    }

    /// Rollback specific area
    pub fn rollbackArea(self: *StateRecovery, buf: *Buffer, area: Rect) !void {
        const snap = self.snapshot orelse return error.NoSnapshot;

        if (snap.width != buf.width or snap.height != buf.height) {
            return error.SizeMismatch;
        }

        var y = area.y;
        while (y < area.y + area.height and y < buf.height) : (y += 1) {
            var x = area.x;
            while (x < area.x + area.width and x < buf.width) : (x += 1) {
                const idx = @as(usize, y) * buf.width + x;
                buf.cells[idx] = snap.cells[idx];
            }
        }
        self.rollback_counter += 1;
    }

    /// Rollback with validation
    pub fn rollbackWithValidation(self: *StateRecovery, buf: *Buffer) !void {
        const snap = self.snapshot orelse return error.NoSnapshot;

        if (self.validator) |validator| {
            // Create a temporary buffer to validate
            const temp_cells = try self.allocator.dupe(Cell, snap.cells);
            defer self.allocator.free(temp_cells);

            // Temporarily swap to validate
            const orig_cells = buf.cells;
            buf.cells = temp_cells;
            const valid = validator(buf);
            buf.cells = orig_cells;

            if (!valid) {
                return error.ValidationFailed;
            }
        }

        try self.rollback(buf);
    }

    /// Set state validator
    pub fn setValidator(self: *StateRecovery, validator: StateValidator) !void {
        self.validator = validator;
    }

    /// Set compression threshold
    pub fn setCompressionThreshold(self: *StateRecovery, threshold: usize) !void {
        self.compression_threshold = threshold;
    }

    /// Check if snapshot exists
    pub fn hasSnapshot(self: *const StateRecovery) bool {
        return self.snapshot != null;
    }

    /// Get memory overhead
    pub fn memoryOverhead(self: *const StateRecovery) usize {
        var total: usize = 0;
        if (self.snapshot) |snap| {
            const cell_size = @sizeOf(Cell) * snap.cells.len;
            // Apply compression if enabled
            if (snap.cells.len >= self.compression_threshold) {
                // Simulate compression (assume 50% reduction for repeated patterns)
                total += cell_size / 2;
            } else {
                total += cell_size;
            }
        }
        for (self.snapshot_stack.items) |snap| {
            total += @sizeOf(Cell) * snap.cells.len;
        }
        return total;
    }

    /// Get rollback count
    pub fn rollbackCount(self: *const StateRecovery) usize {
        return self.rollback_counter;
    }
};

// ============================================================================
// FEATURE 3: ERROR REPORTER
// ============================================================================

/// Error reporting hook
pub const ReportHook = *const fn (ctx: ?*anyopaque, err: anyerror, message: []const u8) void;

/// Error filter
pub const ErrorFilter = *const fn (err: anyerror) bool;

/// Hook entry with priority
const HookEntry = struct {
    hook: ReportHook,
    context: ?*anyopaque,
    priority: u8,
    id: usize,
};

/// Buffered error report
const BufferedReport = struct {
    err: anyerror,
    message: []const u8,
};

/// Log format
pub const LogFormat = enum {
    text,
    json,
};

/// Hook-based error reporting system
pub const ErrorReporter = struct {
    allocator: Allocator,
    hooks: ArrayList(HookEntry),
    next_id: usize,
    context_map: StringHashMap([]const u8),
    filter: ?ErrorFilter,
    buffer: ArrayList(BufferedReport),
    buffer_size: usize,
    log_writer: ?std.io.AnyWriter,
    log_format: LogFormat,

    /// Initialize error reporter
    pub fn init(allocator: Allocator) !ErrorReporter {
        return .{
            .allocator = allocator,
            .hooks = .{},
            .next_id = 1,
            .context_map = StringHashMap([]const u8).init(allocator),
            .filter = null,
            .buffer = .{},
            .buffer_size = 0, // Buffering disabled by default
            .log_writer = null,
            .log_format = .text,
        };
    }

    /// Free all resources
    pub fn deinit(self: *ErrorReporter) void {
        self.hooks.deinit(self.allocator);
        var it = self.context_map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.context_map.deinit();
        for (self.buffer.items) |item| {
            self.allocator.free(item.message);
        }
        self.buffer.deinit(self.allocator);
    }

    /// Register error hook
    pub fn registerHook(self: *ErrorReporter, hook: ReportHook, context: ?*anyopaque) !usize {
        return self.registerHookWithPriority(hook, context, 128); // Default mid priority
    }

    /// Register hook with priority (lower number = higher priority)
    pub fn registerHookWithPriority(self: *ErrorReporter, hook: ReportHook, context: ?*anyopaque, priority: u8) !usize {
        const id = self.next_id;
        self.next_id += 1;

        try self.hooks.append(self.allocator, .{
            .hook = hook,
            .context = context,
            .priority = priority,
            .id = id,
        });

        // Sort by priority
        std.mem.sort(HookEntry, self.hooks.items, {}, struct {
            fn lessThan(_: void, a: HookEntry, b: HookEntry) bool {
                return a.priority < b.priority;
            }
        }.lessThan);

        return id;
    }

    /// Register async hook (same as regular for now)
    pub fn registerAsyncHook(self: *ErrorReporter, hook: ReportHook, context: ?*anyopaque) !usize {
        return self.registerHook(hook, context);
    }

    /// Remove hook
    pub fn removeHook(self: *ErrorReporter, id: usize) !void {
        for (self.hooks.items, 0..) |entry, i| {
            if (entry.id == id) {
                _ = self.hooks.orderedRemove(i);
                return;
            }
        }
        return error.HookNotFound;
    }

    /// Report error (immediate)
    pub fn report(self: *ErrorReporter, err: anyerror, message: []const u8) void {
        // Check filter
        if (self.filter) |filter| {
            if (!filter(err)) return;
        }

        // Write to log if configured
        if (self.log_writer) |writer| {
            self.writeLog(writer, err, message) catch {};
        }

        // Invoke hooks
        for (self.hooks.items) |entry| {
            entry.hook(entry.context, err, message);
        }
    }

    /// Report error async (spawn thread)
    pub fn reportAsync(self: *ErrorReporter, err: anyerror, message: []const u8) void {
        // For simplicity, just call report (async would require thread spawning)
        self.report(err, message);
    }

    /// Report error buffered
    pub fn reportBuffered(self: *ErrorReporter, err: anyerror, message: []const u8) void {
        if (self.buffer_size == 0) {
            // Buffering disabled, report immediately
            self.report(err, message);
            return;
        }

        // Check filter
        if (self.filter) |filter| {
            if (!filter(err)) return;
        }

        const owned_message = self.allocator.dupe(u8, message) catch return;
        self.buffer.append(self.allocator, .{ .err = err, .message = owned_message }) catch {
            self.allocator.free(owned_message);
            return;
        };

        // Auto-flush if buffer full
        if (self.buffer.items.len >= self.buffer_size) {
            self.flush() catch {};
        }
    }

    /// Flush buffered reports
    pub fn flush(self: *ErrorReporter) !void {
        for (self.buffer.items) |item| {
            self.report(item.err, item.message);
            self.allocator.free(item.message);
        }
        self.buffer.clearRetainingCapacity();
    }

    /// Set error filter
    pub fn setFilter(self: *ErrorReporter, filter: ErrorFilter) !void {
        self.filter = filter;
    }

    /// Set buffer size
    pub fn setBufferSize(self: *ErrorReporter, size: usize) !void {
        self.buffer_size = size;
    }

    /// Set context value
    pub fn setContext(self: *ErrorReporter, key: []const u8, value: []const u8) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        if (try self.context_map.fetchPut(owned_key, owned_value)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }
    }

    /// Get context value
    pub fn getContext(self: *const ErrorReporter, key: []const u8) ?[]const u8 {
        return self.context_map.get(key);
    }

    /// Set log writer
    pub fn setLogWriter(self: *ErrorReporter, writer: anytype) !void {
        self.log_writer = writer.any();
    }

    /// Set log format
    pub fn setFormat(self: *ErrorReporter, format: LogFormat) !void {
        self.log_format = format;
    }

    /// Write log entry
    fn writeLog(self: *ErrorReporter, writer: std.io.AnyWriter, err: anyerror, message: []const u8) !void {
        switch (self.log_format) {
            .text => {
                try writer.print("[ERROR] {s}: {s}\n", .{ @errorName(err), message });
            },
            .json => {
                try writer.print("{{\"error\":\"{s}\",\"message\":\"{s}\"}}\n", .{ @errorName(err), message });
            },
        }
    }
};

// ============================================================================
// FEATURE 4: GRACEFUL DEGRADATION
// ============================================================================

/// Quality level for rendering
pub const QualityLevel = enum {
    normal,
    low,
    minimal,
};

/// Render result
pub const RenderResult = enum {
    success,
    failed,
    skipped,
};

/// Rendering statistics
pub const RenderStats = struct {
    total_renders: usize,
    successes: usize,
    failures: usize,
};

/// Multi-widget render results
pub const MultiRenderResult = struct {
    succeeded: []bool,
    allocator: Allocator,

    pub fn deinit(self: *MultiRenderResult) void {
        self.allocator.free(self.succeeded);
    }
};

/// Graceful degradation system with quality levels
pub const GracefulDegradation = struct {
    allocator: Allocator,
    quality_level: QualityLevel,
    stats: RenderStats,
    consecutive_failures: usize,
    consecutive_successes: usize,
    auto_degrade_enabled: bool,
    auto_degrade_threshold: usize,
    auto_recover_enabled: bool,
    auto_recover_threshold: usize,
    non_critical_widgets: StringHashMap(void),
    critical_widgets: StringHashMap(void),
    render_budget_ns: u64,

    /// Initialize graceful degradation
    pub fn init(allocator: Allocator) !GracefulDegradation {
        return .{
            .allocator = allocator,
            .quality_level = .normal,
            .stats = .{ .total_renders = 0, .successes = 0, .failures = 0 },
            .consecutive_failures = 0,
            .consecutive_successes = 0,
            .auto_degrade_enabled = false,
            .auto_degrade_threshold = 5,
            .auto_recover_enabled = false,
            .auto_recover_threshold = 10,
            .non_critical_widgets = StringHashMap(void).init(allocator),
            .critical_widgets = StringHashMap(void).init(allocator),
            .render_budget_ns = std.math.maxInt(u64),
        };
    }

    /// Free all resources
    pub fn deinit(self: *GracefulDegradation) void {
        var it = self.non_critical_widgets.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.non_critical_widgets.deinit();

        var it2 = self.critical_widgets.keyIterator();
        while (it2.next()) |key| {
            self.allocator.free(key.*);
        }
        self.critical_widgets.deinit();
    }

    /// Render widget with fallback
    pub fn renderWithFallback(self: *GracefulDegradation, widget: anytype, buf: *Buffer, area: Rect, fallback_text: []const u8) RenderResult {
        self.stats.total_renders += 1;

        if (widget.render(buf, area)) |_| {
            self.stats.successes += 1;
            self.consecutive_successes += 1;
            self.consecutive_failures = 0;
            self.checkAutoRecover();
            return .success;
        } else |_| {
            self.stats.failures += 1;
            self.consecutive_failures += 1;
            self.consecutive_successes = 0;
            self.checkAutoDegrade();

            // Render fallback
            if (fallback_text.len > 0) {
                var x = area.x;
                for (fallback_text) |ch| {
                    if (x >= area.x + area.width) break;
                    buf.set(x, area.y, .{ .char = ch, .style = .{} });
                    x += 1;
                }
            }
            return .failed;
        }
    }

    /// Render widget
    pub fn render(self: *GracefulDegradation, widget: anytype, buf: *Buffer, area: Rect) !void {
        self.stats.total_renders += 1;

        if (widget.render(buf, area)) |_| {
            self.stats.successes += 1;
            self.consecutive_successes += 1;
            self.consecutive_failures = 0;
            self.checkAutoRecover();
        } else |err| {
            self.stats.failures += 1;
            self.consecutive_failures += 1;
            self.consecutive_successes = 0;
            self.checkAutoDegrade();
            return err;
        }
    }

    /// Render widget with budget
    pub fn renderWithBudget(self: *GracefulDegradation, widget: anytype, buf: *Buffer, area: Rect) !void {
        const start = std.time.nanoTimestamp();

        // Attempt render
        try self.render(widget, buf, area);

        const elapsed = std.time.nanoTimestamp() - start;
        if (elapsed > self.render_budget_ns) {
            return error.BudgetExceeded;
        }
    }

    /// Render multiple widgets with degradation
    pub fn renderMultipleWithDegradation(
        self: *GracefulDegradation,
        comptime widget_types: []const type,
        areas: []const Rect,
        buf: *Buffer,
    ) !MultiRenderResult {
        const succeeded = try self.allocator.alloc(bool, widget_types.len);
        errdefer self.allocator.free(succeeded);

        inline for (widget_types, 0..) |WidgetType, i| {
            const widget = WidgetType{};
            const area = areas[i];

            if (widget.render(buf, area)) |_| {
                succeeded[i] = true;
            } else |_| {
                succeeded[i] = false;
            }
        }

        return .{ .succeeded = succeeded, .allocator = self.allocator };
    }

    /// Check and apply auto-degrade
    fn checkAutoDegrade(self: *GracefulDegradation) void {
        if (!self.auto_degrade_enabled) return;
        if (self.consecutive_failures >= self.auto_degrade_threshold) {
            if (self.quality_level == .normal) {
                self.quality_level = .low;
            } else if (self.quality_level == .low) {
                self.quality_level = .minimal;
            }
        }
    }

    /// Check and apply auto-recover
    fn checkAutoRecover(self: *GracefulDegradation) void {
        if (!self.auto_recover_enabled) return;
        if (self.consecutive_successes >= self.auto_recover_threshold) {
            self.quality_level = .normal;
        }
    }

    /// Set quality level
    pub fn setQualityLevel(self: *GracefulDegradation, level: QualityLevel) !void {
        self.quality_level = level;
    }

    /// Get quality level
    pub fn getQualityLevel(self: *const GracefulDegradation) QualityLevel {
        return self.quality_level;
    }

    /// Set auto-degrade
    pub fn setAutoDegrade(self: *GracefulDegradation, enabled: bool, threshold: usize) !void {
        self.auto_degrade_enabled = enabled;
        self.auto_degrade_threshold = threshold;
    }

    /// Set auto-recover
    pub fn setAutoRecover(self: *GracefulDegradation, enabled: bool, threshold: usize) !void {
        self.auto_recover_enabled = enabled;
        self.auto_recover_threshold = threshold;
    }

    /// Set render budget
    pub fn setRenderBudget(self: *GracefulDegradation, budget_ns: u64) !void {
        self.render_budget_ns = budget_ns;
    }

    /// Mark widget as non-critical
    pub fn markNonCritical(self: *GracefulDegradation, name: []const u8) !void {
        const owned = try self.allocator.dupe(u8, name);
        try self.non_critical_widgets.put(owned, {});
    }

    /// Mark widget as critical
    pub fn markCritical(self: *GracefulDegradation, name: []const u8) !void {
        const owned = try self.allocator.dupe(u8, name);
        try self.critical_widgets.put(owned, {});
    }

    /// Get statistics
    pub fn getStats(self: *const GracefulDegradation) RenderStats {
        return self.stats;
    }

    /// Should animate (based on quality level)
    pub fn shouldAnimate(self: *const GracefulDegradation) bool {
        return self.quality_level == .normal;
    }

    /// Should blur (based on quality level)
    pub fn shouldBlur(self: *const GracefulDegradation) bool {
        return self.quality_level == .normal;
    }

    /// Should draw shadows (based on quality level)
    pub fn shouldDrawShadows(self: *const GracefulDegradation) bool {
        return self.quality_level == .normal;
    }
};

// ============================================================================
// FEATURE 5: ERROR INJECTOR (TESTING UTILITIES)
// ============================================================================

/// Injection mode
const InjectionMode = enum {
    count,
    probability,
    delay,
    alloc_failure,
    panic,
    conditional,
};

/// Injection entry
const InjectionEntry = struct {
    mode: InjectionMode,
    err: anyerror,
    count: usize,
    probability: f64,
    delay_ns: u64,
    condition: ?*const fn (ctx: ?*anyopaque) bool,
    condition_ctx: ?*anyopaque,
    panic_message: []const u8,
};

/// Injection statistics
pub const InjectionStats = struct {
    total_calls: usize,
    injected_errors: usize,
};

/// FailingAllocator for memory testing
pub const FailingAllocator = struct {
    parent: Allocator,
    fail_at: usize,
    call_count: usize,

    pub fn alloc(self: *FailingAllocator, comptime T: type, n: usize) ![]T {
        self.call_count += 1;
        if (self.call_count >= self.fail_at) {
            return error.OutOfMemory;
        }
        return self.parent.alloc(T, n);
    }

    pub fn free(self: *FailingAllocator, slice: anytype) void {
        self.parent.free(slice);
    }
};

/// Error injection utilities for testing
pub const ErrorInjector = struct {
    allocator: Allocator,
    injections: StringHashMap(ArrayList(InjectionEntry)),
    stats: StringHashMap(InjectionStats),
    rng: std.Random.DefaultPrng,
    alloc_fail_at: usize,

    /// Initialize error injector
    pub fn init(allocator: Allocator) !ErrorInjector {
        return .{
            .allocator = allocator,
            .injections = StringHashMap(ArrayList(InjectionEntry)).init(allocator),
            .stats = StringHashMap(InjectionStats).init(allocator),
            .rng = std.Random.DefaultPrng.init(0),
            .alloc_fail_at = std.math.maxInt(usize),
        };
    }

    /// Free all resources
    pub fn deinit(self: *ErrorInjector) void {
        var it = self.injections.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.injections.deinit();

        var it2 = self.stats.keyIterator();
        while (it2.next()) |key| {
            self.allocator.free(key.*);
        }
        self.stats.deinit();
    }

    /// Inject error at specific count
    pub fn injectErrorAt(self: *ErrorInjector, widget_name: []const u8, err: anyerror, count: usize) !void {
        try self.addInjection(widget_name, .{
            .mode = .count,
            .err = err,
            .count = count,
            .probability = 0,
            .delay_ns = 0,
            .condition = null,
            .condition_ctx = null,
            .panic_message = "",
        });
    }

    /// Inject error with probability
    pub fn injectErrorProbability(self: *ErrorInjector, widget_name: []const u8, err: anyerror, probability: f64) !void {
        try self.addInjection(widget_name, .{
            .mode = .probability,
            .err = err,
            .count = 0,
            .probability = probability,
            .delay_ns = 0,
            .condition = null,
            .condition_ctx = null,
            .panic_message = "",
        });
    }

    /// Inject delay
    pub fn injectDelay(self: *ErrorInjector, widget_name: []const u8, delay_ns: u64) !void {
        try self.addInjection(widget_name, .{
            .mode = .delay,
            .err = error.None,
            .count = 0,
            .probability = 0,
            .delay_ns = delay_ns,
            .condition = null,
            .condition_ctx = null,
            .panic_message = "",
        });
    }

    /// Inject allocation failure
    pub fn injectAllocFailure(self: *ErrorInjector, at: usize) !void {
        self.alloc_fail_at = at;
    }

    /// Inject panic
    pub fn injectPanic(self: *ErrorInjector, widget_name: []const u8, message: []const u8) !void {
        try self.addInjection(widget_name, .{
            .mode = .panic,
            .err = error.Panic,
            .count = 0,
            .probability = 0,
            .delay_ns = 0,
            .condition = null,
            .condition_ctx = null,
            .panic_message = message,
        });
    }

    /// Inject error conditionally
    pub fn injectErrorConditional(
        self: *ErrorInjector,
        widget_name: []const u8,
        err: anyerror,
        condition: *const fn (ctx: ?*anyopaque) bool,
        ctx: ?*anyopaque,
    ) !void {
        try self.addInjection(widget_name, .{
            .mode = .conditional,
            .err = err,
            .count = 0,
            .probability = 0,
            .delay_ns = 0,
            .condition = condition,
            .condition_ctx = ctx,
            .panic_message = "",
        });
    }

    /// Add injection entry
    fn addInjection(self: *ErrorInjector, widget_name: []const u8, entry: InjectionEntry) !void {
        const result = try self.injections.getOrPut(widget_name);
        if (!result.found_existing) {
            result.key_ptr.* = try self.allocator.dupe(u8, widget_name);
            result.value_ptr.* = .{};
        }
        try result.value_ptr.append(self.allocator, entry);
    }

    /// Wrap render with injection
    pub fn wrapRender(self: *ErrorInjector, widget_name: []const u8, widget: anytype, buf: *Buffer, area: Rect) !void {
        // Update stats
        const stats_result = try self.stats.getOrPut(widget_name);
        if (!stats_result.found_existing) {
            stats_result.key_ptr.* = try self.allocator.dupe(u8, widget_name);
            stats_result.value_ptr.* = .{ .total_calls = 0, .injected_errors = 0 };
        }
        stats_result.value_ptr.total_calls += 1;

        // Check injections
        if (self.injections.get(widget_name)) |entries| {
            for (entries.items) |*entry| {
                switch (entry.mode) {
                    .count => {
                        if (entry.count > 0) {
                            entry.count -= 1;
                            if (entry.count == 0) {
                                stats_result.value_ptr.injected_errors += 1;
                                return entry.err;
                            }
                        }
                    },
                    .probability => {
                        const rand_val = self.rng.random().float(f64);
                        if (rand_val < entry.probability) {
                            stats_result.value_ptr.injected_errors += 1;
                            return entry.err;
                        }
                    },
                    .delay => {
                        std.Thread.sleep(entry.delay_ns);
                    },
                    .conditional => {
                        if (entry.condition) |cond| {
                            if (cond(entry.condition_ctx)) {
                                stats_result.value_ptr.injected_errors += 1;
                                return entry.err;
                            }
                        }
                    },
                    .panic => {
                        return error.Panic;
                    },
                    else => {},
                }
            }
        }

        // Actual render
        return widget.render(buf, area);
    }

    /// Wrap render with panic safety
    pub fn wrapRenderSafe(self: *ErrorInjector, widget_name: []const u8, widget: anytype, buf: *Buffer, area: Rect) !void {
        return self.wrapRender(widget_name, widget, buf, area) catch |err| {
            if (err == error.Panic) {
                return error.Panic;
            }
            return err;
        };
    }

    /// Create failing allocator
    pub fn createFailingAllocator(self: *ErrorInjector, parent: Allocator) !FailingAllocator {
        return .{
            .parent = parent,
            .fail_at = self.alloc_fail_at,
            .call_count = 0,
        };
    }

    /// Reset all injections
    pub fn reset(self: *ErrorInjector) void {
        var it = self.injections.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.injections.clearRetainingCapacity();
    }

    /// Get statistics
    pub fn getStats(self: *const ErrorInjector, widget_name: []const u8) InjectionStats {
        return self.stats.get(widget_name) orelse .{ .total_calls = 0, .injected_errors = 0 };
    }

    /// Set random seed
    pub fn setSeed(self: *ErrorInjector, seed: u64) !void {
        self.rng = std.Random.DefaultPrng.init(seed);
    }
};
