//! Test Quality Audit Tool
//!
//! Analyzes test files for common quality issues:
//! - Tests with no assertions
//! - Tests that always pass (trivial assertions)
//! - Missing edge case coverage
//! - Unreachable code in test blocks
//!
//! Usage: zig run scripts/test-quality-audit.zig

const std = @import("std");

const TestIssue = struct {
    file: []const u8,
    line: usize,
    test_name: []const u8,
    issue_type: enum {
        no_assertions,
        trivial_assertion,
        unreachable_code,
        missing_error_path,
    },
    description: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Sailor Test Quality Audit ===\n\n", .{});

    // Scan test files
    const test_dirs = [_][]const u8{ "tests", "src" };
    var issues = std.ArrayList(TestIssue){};
    defer issues.deinit(allocator);

    for (test_dirs) |dir| {
        try scanDirectory(allocator, dir, &issues);
    }

    // Report findings
    if (issues.items.len == 0) {
        std.debug.print("✓ No test quality issues found!\n", .{});
        return;
    }

    std.debug.print("Found {} potential test quality issues:\n\n", .{issues.items.len});

    for (issues.items, 1..) |issue, idx| {
        std.debug.print("{}. {s} (line {})\n", .{ idx, issue.file, issue.line });
        std.debug.print("   Test: \"{s}\"\n", .{issue.test_name});
        std.debug.print("   Issue: {s}\n", .{@tagName(issue.issue_type)});
        std.debug.print("   {s}\n\n", .{issue.description});
    }
}

fn scanDirectory(allocator: std.mem.Allocator, dir_path: []const u8, issues: *std.ArrayList(TestIssue)) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .directory) {
            const sub_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
            defer allocator.free(sub_path);
            try scanDirectory(allocator, sub_path, issues);
        } else if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
            defer allocator.free(file_path);
            try analyzeFile(allocator, file_path, issues);
        }
    }
}

fn analyzeFile(allocator: std.mem.Allocator, file_path: []const u8, issues: *std.ArrayList(TestIssue)) !void {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var line_num: usize = 0;
    var in_test: bool = false;
    var current_test_name: []const u8 = "";
    var current_test_line: usize = 0;
    var test_has_assertion: bool = false;

    while (lines.next()) |line| {
        line_num += 1;

        // Detect test start
        if (std.mem.indexOf(u8, line, "test \"") != null) {
            if (in_test and !test_has_assertion) {
                // Previous test had no assertions
                try issues.append(allocator, .{
                    .file = try allocator.dupe(u8, file_path),
                    .line = current_test_line,
                    .test_name = try allocator.dupe(u8, current_test_name),
                    .issue_type = .no_assertions,
                    .description = try allocator.dupe(u8, "Test contains no assertions (try testing.expect/expectEqual)"),
                });
            }

            in_test = true;
            current_test_line = line_num;
            test_has_assertion = false;

            // Extract test name
            if (std.mem.indexOf(u8, line, "test \"")) |start_idx| {
                const name_start = start_idx + 6;
                if (std.mem.indexOfPos(u8, line, name_start, "\"")) |end_idx| {
                    current_test_name = line[name_start..end_idx];
                }
            }
        }

        // Detect assertions
        if (in_test) {
            if (std.mem.indexOf(u8, line, "try testing.expect") != null or
                std.mem.indexOf(u8, line, "try expect") != null or
                std.mem.indexOf(u8, line, "@panic") != null)
            {
                test_has_assertion = true;
            }

            // Detect trivial always-true assertions
            if (std.mem.indexOf(u8, line, "try testing.expect(true)") != null or
                std.mem.indexOf(u8, line, "try expectEqual(true, true)") != null)
            {
                try issues.append(allocator, .{
                    .file = try allocator.dupe(u8, file_path),
                    .line = line_num,
                    .test_name = try allocator.dupe(u8, current_test_name),
                    .issue_type = .trivial_assertion,
                    .description = try allocator.dupe(u8, "Trivial assertion that always passes"),
                });
            }

            // Detect unreachable after try testing.expect(false)
            if (std.mem.indexOf(u8, line, "try testing.expect(false)") != null) {
                const trimmed = std.mem.trim(u8, line, " \t");
                if (!std.mem.startsWith(u8, trimmed, "//")) {
                    try issues.append(allocator, .{
                        .file = try allocator.dupe(u8, file_path),
                        .line = line_num,
                        .test_name = try allocator.dupe(u8, current_test_name),
                        .issue_type = .unreachable_code,
                        .description = try allocator.dupe(u8, "Unconditional expect(false) makes rest of test unreachable"),
                    });
                }
            }
        }

        // Detect test end (closing brace at start of line)
        const trimmed = std.mem.trim(u8, line, " \t");
        if (in_test and std.mem.eql(u8, trimmed, "}")) {
            if (!test_has_assertion) {
                try issues.append(allocator, .{
                    .file = try allocator.dupe(u8, file_path),
                    .line = current_test_line,
                    .test_name = try allocator.dupe(u8, current_test_name),
                    .issue_type = .no_assertions,
                    .description = try allocator.dupe(u8, "Test contains no assertions (try testing.expect/expectEqual)"),
                });
            }
            in_test = false;
        }
    }
}
