//! Result formatting for structured output
//!
//! Provides formatters for table, JSON, CSV, and plain text output.
//! All output is written to user-provided Writer.
//!
//! Features:
//! - Table: auto-width columns, borders, alignment
//! - JSON: streaming output, proper escaping
//! - CSV: configurable delimiter, quoting
//! - Plain: simple key-value pairs

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{} || Allocator.Error;

/// Output format mode
pub const Mode = enum {
    table,
    json,
    csv,
    plain,
};

/// Table alignment
pub const Alignment = enum {
    left,
    right,
    center,
};

/// Table configuration
pub const TableConfig = struct {
    /// Show borders (default: true)
    borders: bool = true,

    /// Show header separator (default: true)
    header_separator: bool = true,

    /// Column alignments (null = all left)
    alignments: ?[]const Alignment = null,

    /// Minimum column width (default: 0)
    min_width: usize = 0,

    /// Maximum column width (default: unlimited)
    max_width: ?usize = null,
};

/// CSV configuration
pub const CsvConfig = struct {
    /// Delimiter character (default: ',')
    delimiter: u8 = ',',

    /// Quote character (default: '"')
    quote: u8 = '"',

    /// Always quote fields (default: false, quote only when needed)
    always_quote: bool = false,
};

/// Table formatter
pub const Table = struct {
    allocator: Allocator,
    config: TableConfig,
    headers: []const []const u8,
    rows: std.ArrayListUnmanaged([]const []const u8),
    widths: []usize,

    const Self = @This();

    /// Initialize table with headers
    pub fn init(allocator: Allocator, headers: []const []const u8, config: TableConfig) !Self {
        const widths = try allocator.alloc(usize, headers.len);
        errdefer allocator.free(widths);

        // Initialize widths with header lengths
        for (headers, 0..) |header, i| {
            widths[i] = @max(header.len, config.min_width);
        }

        return Self{
            .allocator = allocator,
            .config = config,
            .headers = headers,
            .rows = .{},
            .widths = widths,
        };
    }

    /// Cleanup resources
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.widths);
        self.rows.deinit(self.allocator);
    }

    /// Add a row
    pub fn addRow(self: *Self, row: []const []const u8) !void {
        if (row.len != self.headers.len) {
            return error.ColumnCountMismatch;
        }

        // Update column widths
        for (row, 0..) |cell, i| {
            const width = @min(
                if (self.config.max_width) |max| @min(cell.len, max) else cell.len,
                cell.len
            );
            self.widths[i] = @max(self.widths[i], width);
        }

        try self.rows.append(self.allocator, row);
    }

    /// Render table to writer
    pub fn render(self: Self, writer: anytype) !void {
        // Top border
        if (self.config.borders) {
            try self.renderBorder(writer, .top);
        }

        // Header
        try self.renderRow(writer, self.headers);

        // Header separator
        if (self.config.header_separator) {
            try self.renderBorder(writer, .middle);
        }

        // Rows
        for (self.rows.items) |row| {
            try self.renderRow(writer, row);
        }

        // Bottom border
        if (self.config.borders) {
            try self.renderBorder(writer, .bottom);
        }
    }

    const BorderType = enum { top, middle, bottom };

    const BorderChars = struct {
        left: []const u8,
        middle: []const u8,
        right: []const u8,
        horiz: []const u8,
    };

    fn renderBorder(self: Self, writer: anytype, border_type: BorderType) !void {
        const chars: BorderChars = switch (border_type) {
            .top => .{ .left = "┌", .middle = "┬", .right = "┐", .horiz = "─" },
            .middle => .{ .left = "├", .middle = "┼", .right = "┤", .horiz = "─" },
            .bottom => .{ .left = "└", .middle = "┴", .right = "┘", .horiz = "─" },
        };

        try writer.writeAll(chars.left);
        for (self.widths, 0..) |width, i| {
            for (0..width + 2) |_| {
                try writer.writeAll(chars.horiz);
            }
            if (i < self.widths.len - 1) {
                try writer.writeAll(chars.middle);
            }
        }
        try writer.writeAll(chars.right);
        try writer.writeByte('\n');
    }

    fn renderRow(self: Self, writer: anytype, row: []const []const u8) !void {
        if (self.config.borders) {
            try writer.writeAll("│ ");
        }

        for (row, 0..) |cell, i| {
            const alignment = if (self.config.alignments) |aligns|
                aligns[i]
            else
                .left;

            const width = self.widths[i];
            const cell_len = @min(cell.len, width);
            const padding = width -| cell_len;

            switch (alignment) {
                .left => {
                    try writer.writeAll(cell[0..cell_len]);
                    for (0..padding) |_| try writer.writeByte(' ');
                },
                .right => {
                    for (0..padding) |_| try writer.writeByte(' ');
                    try writer.writeAll(cell[0..cell_len]);
                },
                .center => {
                    const left_pad = padding / 2;
                    const right_pad = padding - left_pad;
                    for (0..left_pad) |_| try writer.writeByte(' ');
                    try writer.writeAll(cell[0..cell_len]);
                    for (0..right_pad) |_| try writer.writeByte(' ');
                },
            }

            if (i < row.len - 1) {
                if (self.config.borders) {
                    try writer.writeAll(" │ ");
                } else {
                    try writer.writeAll("  ");
                }
            }
        }

        if (self.config.borders) {
            try writer.writeAll(" │");
        }
        try writer.writeByte('\n');
    }
};

/// JSON array writer (streaming)
pub fn JsonArray(comptime WriterType: type) type {
    return struct {
        writer: WriterType,
        first: bool,

        const Self = @This();

        /// Begin JSON array
        pub fn init(writer: WriterType) !Self {
            try writer.writeAll("[");
            return .{ .writer = writer, .first = true };
        }

        /// Add a string value
        pub fn addString(self: *Self, value: []const u8) !void {
            if (!self.first) try self.writer.writeByte(',');
            self.first = false;

            try self.writer.writeByte('"');
            try writeJsonString(self.writer, value);
            try self.writer.writeByte('"');
        }

        /// Add a number value
        pub fn addNumber(self: *Self, value: anytype) !void {
            if (!self.first) try self.writer.writeByte(',');
            self.first = false;

            try self.writer.print("{d}", .{value});
        }

        /// Add a boolean value
        pub fn addBool(self: *Self, value: bool) !void {
            if (!self.first) try self.writer.writeByte(',');
            self.first = false;

            try self.writer.writeAll(if (value) "true" else "false");
        }

        /// Add null value
        pub fn addNull(self: *Self) !void {
            if (!self.first) try self.writer.writeByte(',');
            self.first = false;

            try self.writer.writeAll("null");
        }

        /// Begin nested object
        pub fn beginObject(self: *Self) !JsonObject(WriterType) {
            if (!self.first) try self.writer.writeByte(',');
            self.first = false;

            return JsonObject(WriterType).init(self.writer);
        }

        /// End JSON array
        pub fn end(self: *Self) !void {
            try self.writer.writeAll("]");
        }
    };
}

/// JSON object writer (streaming)
pub fn JsonObject(comptime WriterType: type) type {
    return struct {
        writer: WriterType,
        first: bool,

        const Self = @This();

        /// Begin JSON object
        pub fn init(writer: WriterType) !Self {
            try writer.writeAll("{");
            return .{ .writer = writer, .first = true };
        }

        /// Add a string field
        pub fn addString(self: *Self, key: []const u8, value: []const u8) !void {
            if (!self.first) try self.writer.writeByte(',');
            self.first = false;

            try self.writer.writeByte('"');
            try writeJsonString(self.writer, key);
            try self.writer.writeAll("\":\"");
            try writeJsonString(self.writer, value);
            try self.writer.writeByte('"');
        }

        /// Add a number field
        pub fn addNumber(self: *Self, key: []const u8, value: anytype) !void {
            if (!self.first) try self.writer.writeByte(',');
            self.first = false;

            try self.writer.writeByte('"');
            try writeJsonString(self.writer, key);
            try self.writer.writeAll("\":");
            try self.writer.print("{d}", .{value});
        }

        /// Add a boolean field
        pub fn addBool(self: *Self, key: []const u8, value: bool) !void {
            if (!self.first) try self.writer.writeByte(',');
            self.first = false;

            try self.writer.writeByte('"');
            try writeJsonString(self.writer, key);
            try self.writer.writeAll("\":");
            try self.writer.writeAll(if (value) "true" else "false");
        }

        /// Add null field
        pub fn addNull(self: *Self, key: []const u8) !void {
            if (!self.first) try self.writer.writeByte(',');
            self.first = false;

            try self.writer.writeByte('"');
            try writeJsonString(self.writer, key);
            try self.writer.writeAll("\":null");
        }

        /// End JSON object
        pub fn end(self: *Self) !void {
            try self.writer.writeAll("}");
        }
    };
}

/// CSV writer
pub fn Csv(comptime WriterType: type) type {
    return struct {
        writer: WriterType,
        config: CsvConfig,
        first_in_row: bool,

        const Self = @This();

        /// Initialize CSV writer
        pub fn init(writer: WriterType, config: CsvConfig) Self {
            return .{ .writer = writer, .config = config, .first_in_row = true };
        }

        /// Write a field
        pub fn writeField(self: *Self, value: []const u8) !void {
            if (!self.first_in_row) {
                try self.writer.writeByte(self.config.delimiter);
            }
            self.first_in_row = false;

            const needs_quote = self.config.always_quote or
                std.mem.indexOfScalar(u8, value, self.config.delimiter) != null or
                std.mem.indexOfScalar(u8, value, self.config.quote) != null or
                std.mem.indexOfScalar(u8, value, '\n') != null;

            if (needs_quote) {
                try self.writer.writeByte(self.config.quote);
                for (value) |c| {
                    if (c == self.config.quote) {
                        try self.writer.writeByte(self.config.quote);
                    }
                    try self.writer.writeByte(c);
                }
                try self.writer.writeByte(self.config.quote);
            } else {
                try self.writer.writeAll(value);
            }
        }

        /// End current row
        pub fn endRow(self: *Self) !void {
            try self.writer.writeByte('\n');
            self.first_in_row = true;
        }
    };
}

/// Helper: write JSON-escaped string
fn writeJsonString(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => try writer.print("\\u{x:0>4}", .{c}),
            else => try writer.writeByte(c),
        }
    }
}

// Tests

test "Table basic" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Name", "Age"}, .{ .borders = false });
    defer table.deinit();

    try table.addRow(&.{"Alice", "30"});
    try table.addRow(&.{"Bob", "25"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Alice") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "30") != null);
}

test "Table with borders" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"ID", "Name"}, .{});
    defer table.deinit();

    try table.addRow(&.{"1", "Test"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "┌") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "│") != null);
}

test "JsonArray" {
    const allocator = std.testing.allocator;

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    var arr = try JsonArray(@TypeOf(buf.writer())).init(buf.writer());
    try arr.addString("hello");
    try arr.addNumber(42);
    try arr.addBool(true);
    try arr.addNull();
    try arr.end();

    const expected = "[\"hello\",42,true,null]";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "JsonObject" {
    const allocator = std.testing.allocator;

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    var obj = try JsonObject(@TypeOf(buf.writer())).init(buf.writer());
    try obj.addString("name", "Alice");
    try obj.addNumber("age", 30);
    try obj.addBool("active", true);
    try obj.end();

    const expected = "{\"name\":\"Alice\",\"age\":30,\"active\":true}";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "Csv basic" {
    const allocator = std.testing.allocator;

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    var csv = Csv(@TypeOf(buf.writer())).init(buf.writer(), .{});
    try csv.writeField("Name");
    try csv.writeField("Age");
    try csv.endRow();
    try csv.writeField("Alice");
    try csv.writeField("30");
    try csv.endRow();

    const expected = "Name,Age\nAlice,30\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "Csv quoting" {
    const allocator = std.testing.allocator;

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    var csv = Csv(@TypeOf(buf.writer())).init(buf.writer(), .{});
    try csv.writeField("Hello, World");
    try csv.endRow();

    const expected = "\"Hello, World\"\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "JSON string escaping" {
    const allocator = std.testing.allocator;

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try writeJsonString(buf.writer(), "hello\n\"world\"");

    const expected = "hello\\n\\\"world\\\"";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "CSV with semicolon delimiter" {
    const allocator = std.testing.allocator;

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    const config = CsvConfig{ .delimiter = ';', .quote = '"', .always_quote = false };
    var csv = Csv(@TypeOf(buf.writer())).init(buf.writer(), config);

    try csv.writeField("Name");
    try csv.writeField("Value");
    try csv.endRow();

    try csv.writeField("Item;1");
    try csv.writeField("100");
    try csv.endRow();

    const expected = "Name;Value\n\"Item;1\";100\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "CSV with newlines in fields" {
    const allocator = std.testing.allocator;

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    const config = CsvConfig{ .delimiter = ',', .quote = '"', .always_quote = false };
    var csv = Csv(@TypeOf(buf.writer())).init(buf.writer(), config);

    try csv.writeField("First\nLine");
    try csv.writeField("Second");
    try csv.endRow();

    const expected = "\"First\nLine\",Second\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "Table with empty cells" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"A", "B", "C"}, .{ .borders = false });
    defer table.deinit();

    try table.addRow(&.{"", "value", ""});
    try table.addRow(&.{"data", "", "item"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const result = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, result, "value") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "data") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "item") != null);
}

test "JsonArray nested objects" {
    const allocator = std.testing.allocator;

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    var arr = try JsonArray(@TypeOf(buf.writer())).init(buf.writer());
    {
        var obj = try arr.beginObject();
        try obj.addString("name", "Alice");
        try obj.addNumber("age", 30);
        try obj.end();
    }
    {
        var obj = try arr.beginObject();
        try obj.addString("name", "Bob");
        try obj.addNumber("age", 25);
        try obj.end();
    }
    try arr.end();

    const expected = "[{\"name\":\"Alice\",\"age\":30},{\"name\":\"Bob\",\"age\":25}]";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "JSON escaping control characters" {
    const allocator = std.testing.allocator;

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try writeJsonString(buf.writer(), "tab\there\r\nbackslash\\");

    const expected = "tab\\there\\r\\nbackslash\\\\";
    try std.testing.expectEqualStrings(expected, buf.items);
}
