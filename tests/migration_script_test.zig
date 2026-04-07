//! Migration script correctness tests for v2.0.0
//!
//! This test suite validates that the migration script (scripts/migrate-to-v2.sh)
//! correctly transforms v1.x code patterns to v2.0.0 patterns.

const std = @import("std");
const testing = std.testing;

/// Test data: input code (v1.x) and expected output (v2.0.0)
const TestCase = struct {
    name: []const u8,
    input: []const u8,
    expected: []const u8,
};

/// Run a migration test case
fn testMigrationPattern(allocator: std.mem.Allocator, test_case: TestCase) !void {
    // Create temporary directory for test
    const tmp_dir = try std.fs.cwd().makeOpenPath("zig-cache/migration-test", .{});
    defer std.fs.cwd().deleteTree("zig-cache/migration-test") catch {};

    // Write input file
    const input_file = try tmp_dir.createFile("test.zig", .{});
    defer input_file.close();
    try input_file.writeAll(test_case.input);

    // Run migration script
    var child = std.process.Child.init(
        &[_][]const u8{ "bash", "scripts/migrate-to-v2.sh", "zig-cache/migration-test/test.zig" },
        allocator,
    );
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const term = try child.spawnAndWait();
    try testing.expect(term == .Exited);

    // Read output file
    const output_file = try tmp_dir.openFile("test.zig", .{});
    defer output_file.close();

    const output = try output_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(output);

    // Verify transformation
    try testing.expectEqualStrings(test_case.expected, output);
}

// Test cases for Buffer API migration

test "migrate Buffer.setChar to Buffer.set" {
    const test_case = TestCase{
        .name = "Buffer.setChar → Buffer.set",
        .input =
        \\buffer.setChar(x, y, 'A', style);
        \\buffer.setChar(0, 0, '@', .{});
        ,
        .expected =
        \\buffer.set(x, y, .{ .char = 'A', .style = style });
        \\buffer.set(0, 0, .{ .char = '@', .style = .{} });
        ,
    };

    try testMigrationPattern(testing.allocator, test_case);
}

test "migrate Color basic enum to simplified syntax" {
    const test_case = TestCase{
        .name = "Color{ .basic = .red } → .red",
        .input =
        \\const style = Style{ .fg = Color{ .basic = .red } };
        \\const bg = Color{ .basic = .blue };
        ,
        .expected =
        \\const style = Style{ .fg = .red };
        \\const bg = .blue;
        ,
    };

    try testMigrationPattern(testing.allocator, test_case);
}

test "migrate Rect.new to struct literal" {
    const test_case = TestCase{
        .name = "Rect.new(...) → Rect{ ... }",
        .input =
        \\const rect = Rect.new(0, 0, 80, 24);
        \\var area = Rect.new(x, y, w, h);
        ,
        .expected =
        \\const rect = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
        \\var area = Rect{ .x = x, .y = y, .width = w, .height = h };
        ,
    };

    try testMigrationPattern(testing.allocator, test_case);
}

test "migrate Block.withTitle to struct literal" {
    const test_case = TestCase{
        .name = "Block.withTitle → .title field",
        .input =
        \\var block = Block{}.withTitle("Title", .center);
        ,
        .expected =
        \\var block = Block{ .title = "Title", .title_position = .center };
        ,
    };

    try testMigrationPattern(testing.allocator, test_case);
}

test "migrate Constraint.Length to struct literal" {
    const test_case = TestCase{
        .name = "Constraint.Length(N) → .{ .length = N }",
        .input =
        \\const constraints = [_]Constraint{ Constraint.Length(10), Constraint.Percentage(50) };
        ,
        .expected =
        \\const constraints = [_]Constraint{ .{ .length = 10 }, .{ .percentage = 50 } };
        ,
    };

    try testMigrationPattern(testing.allocator, test_case);
}

// Integration tests with realistic code samples

test "migrate complete widget rendering code" {
    const test_case = TestCase{
        .name = "Complete widget example",
        .input =
        \\pub fn render(self: *Widget, buf: *Buffer, area: Rect) void {
        \\    const block = Block{}.withTitle("Demo", .center);
        \\    const inner = area.inner(1);
        \\
        \\    buf.setChar(0, 0, '▓', Style{ .fg = Color{ .basic = .cyan } });
        \\
        \\    const rect = Rect.new(inner.x, inner.y, 20, 5);
        \\}
        ,
        .expected =
        \\pub fn render(self: *Widget, buf: *Buffer, area: Rect) void {
        \\    const block = Block{ .title = "Demo", .title_position = .center };
        \\    const inner = area.inner(1);
        \\
        \\    buf.set(0, 0, .{ .char = '▓', .style = Style{ .fg = .cyan } });
        \\
        \\    const rect = Rect{ .x = inner.x, .y = inner.y, .width = 20, .height = 5 };
        \\}
        ,
    };

    try testMigrationPattern(testing.allocator, test_case);
}

test "migrate layout constraints" {
    const test_case = TestCase{
        .name = "Layout with constraints",
        .input =
        \\const chunks = layout.split(
        \\    .vertical,
        \\    area,
        \\    &[_]Constraint{
        \\        Constraint.Length(3),
        \\        Constraint.Min(0),
        \\        Constraint.Length(1),
        \\    },
        \\);
        ,
        .expected =
        \\const chunks = layout.split(
        \\    .vertical,
        \\    area,
        \\    &[_]Constraint{
        \\        .{ .length = 3 },
        \\        .{ .min = 0 },
        \\        .{ .length = 1 },
        \\    },
        \\);
        ,
    };

    try testMigrationPattern(testing.allocator, test_case);
}

// Edge case tests

test "preserve correct v2.0.0 code unchanged" {
    const test_case = TestCase{
        .name = "Already migrated code",
        .input =
        \\buf.set(x, y, .{ .char = 'X', .style = .{} });
        \\const style = Style{ .fg = .red };
        \\const rect = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
        ,
        .expected =
        \\buf.set(x, y, .{ .char = 'X', .style = .{} });
        \\const style = Style{ .fg = .red };
        \\const rect = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
        ,
    };

    try testMigrationPattern(testing.allocator, test_case);
}

test "handle multiline Buffer.setChar calls" {
    const test_case = TestCase{
        .name = "Multiline setChar",
        .input =
        \\buffer.setChar(
        \\    x,
        \\    y,
        \\    '█',
        \\    Style{ .fg = Color{ .basic = .green } }
        \\);
        ,
        // Note: Multiline formatting is collapsed during transformation
        // AST-based tool would be needed to preserve exact formatting
        .expected =
        \\buffer.set(x, y, .{ .char = '█', .style = Style{ .fg = .green } });
        ,
    };

    try testMigrationPattern(testing.allocator, test_case);
}

test "handle comments and whitespace preservation" {
    const test_case = TestCase{
        .name = "Comments and formatting",
        .input =
        \\// Set the character
        \\buffer.setChar(x, y, 'A', style);  // inline comment
        \\
        \\// Another operation
        ,
        .expected =
        \\// Set the character
        \\buffer.set(x, y, .{ .char = 'A', .style = style });  // inline comment
        \\
        \\// Another operation
        ,
    };

    try testMigrationPattern(testing.allocator, test_case);
}

// Performance regression test

test "migration script completes within timeout" {
    const allocator = testing.allocator;

    // Create a moderately large file (1000 lines)
    const tmp_dir = try std.fs.cwd().makeOpenPath("zig-cache/migration-perf-test", .{});
    defer std.fs.cwd().deleteTree("zig-cache/migration-perf-test") catch {};

    const input_file = try tmp_dir.createFile("large.zig", .{});
    defer input_file.close();

    // Generate repetitive code
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        var buf: [256]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf,
            "buffer.setChar({d}, {d}, 'X', Style{{ .fg = Color{{ .basic = .red }} }});\n",
            .{ i % 80, i / 80 });
        try input_file.writeAll(line);
    }

    // Run migration with timeout
    var child = std.process.Child.init(
        &[_][]const u8{ "bash", "scripts/migrate-to-v2.sh", "zig-cache/migration-perf-test/large.zig" },
        allocator,
    );
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const start = std.time.milliTimestamp();
    const term = try child.spawnAndWait();
    const elapsed = std.time.milliTimestamp() - start;

    try testing.expect(term == .Exited);
    try testing.expect(elapsed < 5000); // Should complete in < 5 seconds
}

// Idempotency test

test "migration script is idempotent" {
    const allocator = testing.allocator;

    const tmp_dir = try std.fs.cwd().makeOpenPath("zig-cache/migration-idempotent-test", .{});
    defer std.fs.cwd().deleteTree("zig-cache/migration-idempotent-test") catch {};

    const input =
        \\buffer.setChar(x, y, 'A', Style{ .fg = Color{ .basic = .red } });
    ;

    // Write initial file
    {
        const file = try tmp_dir.createFile("test.zig", .{});
        defer file.close();
        try file.writeAll(input);
    }

    // Run migration once
    {
        var child = std.process.Child.init(
            &[_][]const u8{ "bash", "scripts/migrate-to-v2.sh", "zig-cache/migration-idempotent-test/test.zig" },
            allocator,
        );
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        _ = try child.spawnAndWait();
    }

    // Read result
    const first_result = blk: {
        const file = try tmp_dir.openFile("test.zig", .{});
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, 1024);
    };
    defer allocator.free(first_result);

    // Run migration again
    {
        var child = std.process.Child.init(
            &[_][]const u8{ "bash", "scripts/migrate-to-v2.sh", "zig-cache/migration-idempotent-test/test.zig" },
            allocator,
        );
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        _ = try child.spawnAndWait();
    }

    // Read result again
    const second_result = blk: {
        const file = try tmp_dir.openFile("test.zig", .{});
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, 1024);
    };
    defer allocator.free(second_result);

    // Should be identical
    try testing.expectEqualStrings(first_result, second_result);
}
