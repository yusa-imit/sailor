const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const arg = sailor.arg;

test "Parser with argument groups" {
    const flags = [_]arg.FlagDef{
        .{ .name = "input", .short = 'i', .type = .string, .help = "Input file", .group = "Input Options" },
        .{ .name = "format", .type = .string, .help = "Input format", .group = "Input Options" },
        .{ .name = "output", .short = 'o', .type = .string, .help = "Output file", .group = "Output Options" },
        .{ .name = "compress", .type = .bool, .help = "Compress output", .group = "Output Options" },
        .{ .name = "verbose", .short = 'v', .type = .bool, .help = "Verbose logging", .group = "Logging" },
        .{ .name = "log-file", .type = .string, .help = "Log file path", .group = "Logging" },
    };

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const P = arg.Parser(&flags);
    try P.writeHelp(writer);

    const help = fbs.getWritten();

    // Should have group headers
    try testing.expect(std.mem.indexOf(u8, help, "Input Options:") != null);
    try testing.expect(std.mem.indexOf(u8, help, "Output Options:") != null);
    try testing.expect(std.mem.indexOf(u8, help, "Logging:") != null);

    // Flags should appear after their group header
    const input_opts_pos = std.mem.indexOf(u8, help, "Input Options:").?;
    const input_flag_pos = std.mem.indexOf(u8, help, "--input").?;
    try testing.expect(input_flag_pos > input_opts_pos);

    const output_opts_pos = std.mem.indexOf(u8, help, "Output Options:").?;
    const output_flag_pos = std.mem.indexOf(u8, help, "--output").?;
    try testing.expect(output_flag_pos > output_opts_pos);
}

test "Parser with mixed grouped and ungrouped flags" {
    const flags = [_]arg.FlagDef{
        .{ .name = "verbose", .short = 'v', .type = .bool, .help = "Verbose mode" },
        .{ .name = "input", .type = .string, .help = "Input file", .group = "Input" },
        .{ .name = "output", .type = .string, .help = "Output file", .group = "Output" },
        .{ .name = "quiet", .short = 'q', .type = .bool, .help = "Quiet mode" },
    };

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const P = arg.Parser(&flags);
    try P.writeHelp(writer);

    const help = fbs.getWritten();

    // Should have "Options:" for ungrouped flags
    try testing.expect(std.mem.indexOf(u8, help, "Options:") != null);

    // Should have custom group names
    try testing.expect(std.mem.indexOf(u8, help, "Input:") != null);
    try testing.expect(std.mem.indexOf(u8, help, "Output:") != null);

    // Ungrouped flags should be under "Options:"
    const options_pos = std.mem.indexOf(u8, help, "Options:").?;
    const verbose_pos = std.mem.indexOf(u8, help, "--verbose").?;
    try testing.expect(verbose_pos > options_pos);
}

test "Parser argument groups don't affect parsing behavior" {
    const flags = [_]arg.FlagDef{
        .{ .name = "input", .short = 'i', .type = .string, .group = "Input" },
        .{ .name = "verbose", .short = 'v', .type = .bool, .group = "Logging" },
    };

    var parser = arg.Parser(&flags).init(testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{ "-i", "file.txt", "-v" };
    try parser.parse(&args);

    try testing.expectEqualStrings("file.txt", parser.getString("input", ""));
    try testing.expect(parser.getBool("verbose", false));
}
