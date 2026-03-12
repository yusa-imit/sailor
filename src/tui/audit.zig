const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Event = @import("tui.zig").Event;

/// Audit logging system for compliance and security monitoring.
/// Logs all user interactions with configurable filtering and retention policies.
pub const AuditLogger = struct {
    allocator: Allocator,
    entries: ArrayList(AuditEntry),
    enabled: bool,
    max_entries: usize, // 0 = unlimited
    filter: LogFilter,
    session_id: []const u8,

    pub const AuditEntry = struct {
        timestamp: i64, // Unix milliseconds
        session_id: []const u8,
        user_id: ?[]const u8,
        event_type: EventType,
        details: []const u8,
        severity: Severity,

        pub const EventType = enum {
            key_press,
            mouse_click,
            resize,
            navigation,
            data_access,
            data_modification,
            authentication,
            authorization,
            system_error,
            system,
        };

        pub const Severity = enum {
            debug,
            info,
            warning,
            critical,

            pub fn toStr(self: Severity) []const u8 {
                return switch (self) {
                    .debug => "DEBUG",
                    .info => "INFO",
                    .warning => "WARN",
                    .critical => "CRIT",
                };
            }
        };
    };

    pub const LogFilter = struct {
        min_severity: AuditEntry.Severity,
        event_types: ?[]const AuditEntry.EventType, // null = all types
        include_user_ids: ?[]const []const u8, // null = all users
        exclude_event_types: ?[]const AuditEntry.EventType, // null = no exclusions

        pub fn default() LogFilter {
            return .{
                .min_severity = .info,
                .event_types = null,
                .include_user_ids = null,
                .exclude_event_types = null,
            };
        }

        pub fn allEvents() LogFilter {
            return .{
                .min_severity = .debug,
                .event_types = null,
                .include_user_ids = null,
                .exclude_event_types = null,
            };
        }
    };

    pub fn init(allocator: Allocator, session_id: []const u8) !AuditLogger {
        return AuditLogger{
            .allocator = allocator,
            .entries = .{},
            .enabled = true,
            .max_entries = 10000, // Default retention
            .filter = LogFilter.default(),
            .session_id = try allocator.dupe(u8, session_id),
        };
    }

    pub fn deinit(self: *AuditLogger) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.details);
            if (entry.user_id) |uid| self.allocator.free(uid);
        }
        self.entries.deinit(self.allocator);
        self.allocator.free(self.session_id);
    }

    /// Enable or disable audit logging.
    pub fn setEnabled(self: *AuditLogger, enabled: bool) void {
        self.enabled = enabled;
    }

    /// Set maximum number of entries to retain (0 = unlimited).
    pub fn setMaxEntries(self: *AuditLogger, max: usize) void {
        self.max_entries = max;
        self.trimEntries();
    }

    /// Set log filter.
    pub fn setFilter(self: *AuditLogger, filter: LogFilter) void {
        self.filter = filter;
    }

    /// Log a user interaction event.
    pub fn logEvent(
        self: *AuditLogger,
        event_type: AuditEntry.EventType,
        details: []const u8,
        severity: AuditEntry.Severity,
        user_id: ?[]const u8,
    ) !void {
        if (!self.enabled) return;

        // Apply filter
        if (!self.shouldLog(event_type, severity, user_id)) return;

        const entry = AuditEntry{
            .timestamp = std.time.milliTimestamp(),
            .session_id = self.session_id,
            .user_id = if (user_id) |uid| try self.allocator.dupe(u8, uid) else null,
            .event_type = event_type,
            .details = try self.allocator.dupe(u8, details),
            .severity = severity,
        };

        try self.entries.append(self.allocator, entry);
        self.trimEntries();
    }

    /// Log a TUI event (convenience wrapper).
    pub fn logTuiEvent(self: *AuditLogger, event: Event, user_id: ?[]const u8) !void {
        const event_type: AuditEntry.EventType = switch (event) {
            .key => .key_press,
            .mouse => .mouse_click,
            .resize => .resize,
            .gamepad, .touch => .navigation,
        };

        var buf: [256]u8 = undefined;
        const details = switch (event) {
            .key => |k| try std.fmt.bufPrint(&buf, "key={s}", .{@tagName(k.code)}),
            .mouse => |m| try std.fmt.bufPrint(&buf, "x={d},y={d}", .{ m.x, m.y }),
            .resize => |r| try std.fmt.bufPrint(&buf, "w={d},h={d}", .{ r.width, r.height }),
            .gamepad => "gamepad_input",
            .touch => "touch_input",
        };

        try self.logEvent(event_type, details, .debug, user_id);
    }

    /// Log data access.
    pub fn logDataAccess(self: *AuditLogger, resource: []const u8, user_id: ?[]const u8) !void {
        var buf: [512]u8 = undefined;
        const details = try std.fmt.bufPrint(&buf, "resource={s}", .{resource});
        try self.logEvent(.data_access, details, .info, user_id);
    }

    /// Log data modification.
    pub fn logDataModification(self: *AuditLogger, resource: []const u8, action: []const u8, user_id: ?[]const u8) !void {
        var buf: [512]u8 = undefined;
        const details = try std.fmt.bufPrint(&buf, "resource={s},action={s}", .{ resource, action });
        try self.logEvent(.data_modification, details, .warning, user_id);
    }

    /// Log authentication event.
    pub fn logAuthentication(self: *AuditLogger, user_id: []const u8, success: bool) !void {
        var buf: [256]u8 = undefined;
        const details = try std.fmt.bufPrint(&buf, "user={s},success={}", .{ user_id, success });
        const severity: AuditEntry.Severity = if (success) .info else .warning;
        try self.logEvent(.authentication, details, severity, user_id);
    }

    /// Log authorization failure.
    pub fn logAuthorizationFailure(self: *AuditLogger, user_id: []const u8, resource: []const u8) !void {
        var buf: [512]u8 = undefined;
        const details = try std.fmt.bufPrint(&buf, "user={s},resource={s}", .{ user_id, resource });
        try self.logEvent(.authorization, details, .critical, user_id);
    }

    /// Log system error.
    pub fn logError(self: *AuditLogger, error_msg: []const u8) !void {
        try self.logEvent(.system_error, error_msg, .critical, null);
    }

    /// Write audit log to a file (append mode).
    pub fn writeToFile(self: *AuditLogger, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
        defer file.close();

        // Seek to end for append
        try file.seekFromEnd(0);

        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);

        for (self.entries.items) |entry| {
            try writer.print("{d}|{s}|{s}|{s}|", .{
                entry.timestamp,
                entry.session_id,
                entry.severity.toStr(),
                @tagName(entry.event_type),
            });

            if (entry.user_id) |uid| {
                try writer.print("{s}|", .{uid});
            } else {
                try writer.print("system|", .{});
            }

            try writer.print("{s}\n", .{entry.details});
        }

        try file.writeAll(buf.items);
    }

    /// Export to JSON format.
    pub fn exportJson(self: *AuditLogger, writer: anytype) !void {
        try writer.writeAll("[\n");
        for (self.entries.items, 0..) |entry, i| {
            try writer.writeAll("  {");
            try writer.print("\"timestamp\":{d},", .{entry.timestamp});
            try writer.print("\"session\":\"{s}\",", .{entry.session_id});
            try writer.print("\"severity\":\"{s}\",", .{entry.severity.toStr()});
            try writer.print("\"type\":\"{s}\",", .{@tagName(entry.event_type)});

            if (entry.user_id) |uid| {
                try writer.print("\"user\":\"{s}\",", .{uid});
            }

            try writer.print("\"details\":\"{s}\"", .{entry.details});
            try writer.writeAll("}");

            if (i < self.entries.items.len - 1) {
                try writer.writeAll(",\n");
            } else {
                try writer.writeAll("\n");
            }
        }
        try writer.writeAll("]\n");
    }

    /// Get entries count.
    pub fn count(self: *AuditLogger) usize {
        return self.entries.items.len;
    }

    /// Clear all entries.
    pub fn clear(self: *AuditLogger) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.details);
            if (entry.user_id) |uid| self.allocator.free(uid);
        }
        self.entries.clearRetainingCapacity();
    }

    /// Get entries filtered by criteria.
    pub fn getEntries(self: *AuditLogger, allocator: Allocator, event_type: ?AuditEntry.EventType, user_id: ?[]const u8) ![]const AuditEntry {
        var filtered: ArrayList(AuditEntry) = .{};
        errdefer filtered.deinit(allocator);

        for (self.entries.items) |entry| {
            if (event_type) |et| {
                if (entry.event_type != et) continue;
            }

            if (user_id) |uid| {
                if (entry.user_id == null) continue;
                if (!std.mem.eql(u8, entry.user_id.?, uid)) continue;
            }

            try filtered.append(allocator, entry);
        }

        return filtered.toOwnedSlice(allocator);
    }

    // Private helpers

    fn shouldLog(self: *AuditLogger, event_type: AuditEntry.EventType, severity: AuditEntry.Severity, user_id: ?[]const u8) bool {
        // Check severity
        if (@intFromEnum(severity) < @intFromEnum(self.filter.min_severity)) return false;

        // Check excluded event types
        if (self.filter.exclude_event_types) |excluded| {
            for (excluded) |et| {
                if (et == event_type) return false;
            }
        }

        // Check allowed event types
        if (self.filter.event_types) |allowed| {
            var found = false;
            for (allowed) |et| {
                if (et == event_type) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }

        // Check user filter
        if (self.filter.include_user_ids) |users| {
            if (user_id == null) return false;
            var found = false;
            for (users) |uid| {
                if (std.mem.eql(u8, uid, user_id.?)) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }

        return true;
    }

    fn trimEntries(self: *AuditLogger) void {
        if (self.max_entries == 0) return;
        if (self.entries.items.len <= self.max_entries) return;

        const to_remove = self.entries.items.len - self.max_entries;
        for (self.entries.items[0..to_remove]) |entry| {
            self.allocator.free(entry.details);
            if (entry.user_id) |uid| self.allocator.free(uid);
        }

        // Shift remaining items to front
        std.mem.copyForwards(AuditEntry, self.entries.items[0..], self.entries.items[to_remove..]);
        self.entries.items.len -= to_remove;
    }
};

// Tests
test "AuditLogger: init and deinit" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test-session-123");
    defer logger.deinit();

    try std.testing.expect(logger.enabled);
    try std.testing.expectEqual(@as(usize, 0), logger.count());
    try std.testing.expectEqualStrings("test-session-123", logger.session_id);
}

test "AuditLogger: log basic event" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test-session");
    defer logger.deinit();

    try logger.logEvent(.data_access, "file.txt", .info, "user1");

    try std.testing.expectEqual(@as(usize, 1), logger.count());
    const entry = logger.entries.items[0];
    try std.testing.expectEqual(AuditLogger.AuditEntry.EventType.data_access, entry.event_type);
    try std.testing.expectEqual(AuditLogger.AuditEntry.Severity.info, entry.severity);
    try std.testing.expectEqualStrings("file.txt", entry.details);
    try std.testing.expectEqualStrings("user1", entry.user_id.?);
}

test "AuditLogger: log TUI events" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "tui-session");
    defer logger.deinit();

    // TUI events are logged at debug level, so we need to enable debug logging
    logger.setFilter(AuditLogger.LogFilter.allEvents());

    try logger.logTuiEvent(.{ .key = .{ .code = .enter } }, "user1");
    try logger.logTuiEvent(.{ .resize = .{ .width = 80, .height = 24 } }, "user1");

    try std.testing.expectEqual(@as(usize, 2), logger.count());
}

test "AuditLogger: enable/disable" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    logger.setEnabled(false);
    try logger.logEvent(.system, "test", .info, null);
    try std.testing.expectEqual(@as(usize, 0), logger.count());

    logger.setEnabled(true);
    try logger.logEvent(.system, "test", .info, null);
    try std.testing.expectEqual(@as(usize, 1), logger.count());
}

test "AuditLogger: max entries retention" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    logger.setMaxEntries(3);

    try logger.logEvent(.system, "event1", .info, null);
    try logger.logEvent(.system, "event2", .info, null);
    try logger.logEvent(.system, "event3", .info, null);
    try std.testing.expectEqual(@as(usize, 3), logger.count());

    // Adding 4th should remove oldest
    try logger.logEvent(.system, "event4", .info, null);
    try std.testing.expectEqual(@as(usize, 3), logger.count());
    try std.testing.expectEqualStrings("event2", logger.entries.items[0].details);
}

test "AuditLogger: severity filter" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    logger.setFilter(.{
        .min_severity = .warning,
        .event_types = null,
        .include_user_ids = null,
        .exclude_event_types = null,
    });

    try logger.logEvent(.system, "debug", .debug, null);
    try logger.logEvent(.system, "info", .info, null);
    try logger.logEvent(.system, "warning", .warning, null);
    try logger.logEvent(.system, "critical", .critical, null);

    try std.testing.expectEqual(@as(usize, 2), logger.count()); // Only warning and critical
}

test "AuditLogger: event type filter" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    const allowed_types = [_]AuditLogger.AuditEntry.EventType{ .data_access, .data_modification };
    logger.setFilter(.{
        .min_severity = .debug,
        .event_types = &allowed_types,
        .include_user_ids = null,
        .exclude_event_types = null,
    });

    try logger.logEvent(.data_access, "test", .info, null);
    try logger.logEvent(.key_press, "test", .info, null);
    try logger.logEvent(.data_modification, "test", .info, null);

    try std.testing.expectEqual(@as(usize, 2), logger.count());
}

test "AuditLogger: exclude event types" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    const excluded_types = [_]AuditLogger.AuditEntry.EventType{.key_press};
    logger.setFilter(.{
        .min_severity = .debug,
        .event_types = null,
        .include_user_ids = null,
        .exclude_event_types = &excluded_types,
    });

    try logger.logEvent(.key_press, "excluded", .info, null);
    try logger.logEvent(.data_access, "included", .info, null);

    try std.testing.expectEqual(@as(usize, 1), logger.count());
}

test "AuditLogger: user filter" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    const users = [_][]const u8{"alice"};
    logger.setFilter(.{
        .min_severity = .debug,
        .event_types = null,
        .include_user_ids = &users,
        .exclude_event_types = null,
    });

    try logger.logEvent(.data_access, "test", .info, "alice");
    try logger.logEvent(.data_access, "test", .info, "bob");
    try logger.logEvent(.data_access, "test", .info, null);

    try std.testing.expectEqual(@as(usize, 1), logger.count());
}

test "AuditLogger: log data access" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    try logger.logDataAccess("/api/users", "admin");

    try std.testing.expectEqual(@as(usize, 1), logger.count());
    try std.testing.expectEqual(AuditLogger.AuditEntry.EventType.data_access, logger.entries.items[0].event_type);
}

test "AuditLogger: log data modification" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    try logger.logDataModification("/api/users/123", "update", "admin");

    try std.testing.expectEqual(@as(usize, 1), logger.count());
    try std.testing.expectEqual(AuditLogger.AuditEntry.EventType.data_modification, logger.entries.items[0].event_type);
    try std.testing.expectEqual(AuditLogger.AuditEntry.Severity.warning, logger.entries.items[0].severity);
}

test "AuditLogger: log authentication" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    try logger.logAuthentication("alice", true);
    try logger.logAuthentication("bob", false);

    try std.testing.expectEqual(@as(usize, 2), logger.count());
    try std.testing.expectEqual(AuditLogger.AuditEntry.Severity.info, logger.entries.items[0].severity);
    try std.testing.expectEqual(AuditLogger.AuditEntry.Severity.warning, logger.entries.items[1].severity);
}

test "AuditLogger: log authorization failure" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    try logger.logAuthorizationFailure("bob", "/admin/panel");

    try std.testing.expectEqual(@as(usize, 1), logger.count());
    try std.testing.expectEqual(AuditLogger.AuditEntry.EventType.authorization, logger.entries.items[0].event_type);
    try std.testing.expectEqual(AuditLogger.AuditEntry.Severity.critical, logger.entries.items[0].severity);
}

test "AuditLogger: log error" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    try logger.logError("Database connection failed");

    try std.testing.expectEqual(@as(usize, 1), logger.count());
    try std.testing.expectEqual(AuditLogger.AuditEntry.EventType.system_error, logger.entries.items[0].event_type);
    try std.testing.expectEqual(AuditLogger.AuditEntry.Severity.critical, logger.entries.items[0].severity);
}

test "AuditLogger: write to file" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    try logger.logEvent(.data_access, "file.txt", .info, "user1");
    try logger.logEvent(.data_modification, "file.txt", .warning, "user1");

    const test_file = "test_audit.log";
    try logger.writeToFile(test_file);
    defer std.fs.cwd().deleteFile(test_file) catch {};

    const file = try std.fs.cwd().openFile(test_file, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "INFO") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "WARN") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "user1") != null);
}

test "AuditLogger: export JSON" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    try logger.logEvent(.data_access, "test.txt", .info, "alice");

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try logger.exportJson(writer);

    const json = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, json, "\"timestamp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"session\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"user\":\"alice\"") != null);
}

test "AuditLogger: clear entries" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    try logger.logEvent(.system, "test1", .info, null);
    try logger.logEvent(.system, "test2", .info, null);
    try std.testing.expectEqual(@as(usize, 2), logger.count());

    logger.clear();
    try std.testing.expectEqual(@as(usize, 0), logger.count());
}

test "AuditLogger: get filtered entries" {
    const allocator = std.testing.allocator;
    var logger = try AuditLogger.init(allocator, "test");
    defer logger.deinit();

    try logger.logEvent(.data_access, "file1.txt", .info, "alice");
    try logger.logEvent(.data_modification, "file2.txt", .warning, "alice");
    try logger.logEvent(.data_access, "file3.txt", .info, "bob");

    const alice_entries = try logger.getEntries(allocator, null, "alice");
    defer allocator.free(alice_entries);
    try std.testing.expectEqual(@as(usize, 2), alice_entries.len);

    const access_entries = try logger.getEntries(allocator, .data_access, null);
    defer allocator.free(access_entries);
    try std.testing.expectEqual(@as(usize, 2), access_entries.len);
}
