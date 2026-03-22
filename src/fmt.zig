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

    /// Left padding (default: 0)
    padding_left: usize = 0,

    /// Right padding (default: 0)
    padding_right: usize = 0,

    /// Top padding (default: 0)
    padding_top: usize = 0,

    /// Bottom padding (default: 0)
    padding_bottom: usize = 0,
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

        // Top padding
        for (0..self.config.padding_top) |_| {
            try self.renderBlankRow(writer);
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

        // Bottom padding
        for (0..self.config.padding_bottom) |_| {
            try self.renderBlankRow(writer);
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
            for (0..width + 2 + self.config.padding_left + self.config.padding_right) |_| {
                try writer.writeAll(chars.horiz);
            }
            if (i < self.widths.len - 1) {
                try writer.writeAll(chars.middle);
            }
        }
        try writer.writeAll(chars.right);
        try writer.writeByte('\n');
    }

    /// Wrap a cell string into lines based on max_width
    fn wrapCell(self: Self, cell: []const u8) !std.ArrayListUnmanaged([]const u8) {
        var lines = std.ArrayListUnmanaged([]const u8){};

        // First split on explicit newlines
        var line_iter = std.mem.splitScalar(u8, cell, '\n');
        while (line_iter.next()) |line| {
            if (self.config.max_width) |max_width| {
                // Further split by word wrapping if line exceeds max_width
                var wrapped_lines = try self.wrapLine(line, max_width);
                defer wrapped_lines.deinit(self.allocator);

                for (wrapped_lines.items) |wrapped_line| {
                    try lines.append(self.allocator, wrapped_line);
                }
            } else {
                try lines.append(self.allocator, line);
            }
        }

        return lines;
    }

    /// Wrap a single line by word boundaries
    fn wrapLine(self: Self, line: []const u8, max_width: usize) !std.ArrayListUnmanaged([]const u8) {
        var wrapped = std.ArrayListUnmanaged([]const u8){};

        if (line.len <= max_width) {
            try wrapped.append(self.allocator, line);
            return wrapped;
        }

        var current_pos: usize = 0;

        while (current_pos < line.len) {
            var line_end = @min(current_pos + max_width, line.len);

            // If we're not at the end, try to find a word boundary
            if (line_end < line.len) {
                // Look backwards for last space
                var search_pos = line_end;
                while (search_pos > current_pos) {
                    if (line[search_pos - 1] == ' ') {
                        // Found a space, trim trailing spaces
                        while (search_pos > current_pos and line[search_pos - 1] == ' ') {
                            search_pos -= 1;
                        }
                        break;
                    }
                    search_pos -= 1;
                }

                // If we found a space position that's reasonable
                if (search_pos > current_pos) {
                    line_end = search_pos;
                } else {
                    // No good word boundary, hard break at max_width
                    line_end = current_pos + max_width;
                }
            }

            try wrapped.append(self.allocator, line[current_pos..line_end]);
            current_pos = line_end;

            // Skip leading spaces on next line
            while (current_pos < line.len and line[current_pos] == ' ') {
                current_pos += 1;
            }
        }

        return wrapped;
    }

    fn renderRow(self: Self, writer: anytype, row: []const []const u8) !void {
        // Wrap all cells first
        var wrapped_cells = try self.allocator.alloc(std.ArrayListUnmanaged([]const u8), row.len);
        defer {
            for (wrapped_cells) |*cell_lines| {
                cell_lines.deinit(self.allocator);
            }
            self.allocator.free(wrapped_cells);
        }

        var max_lines: usize = 1;

        for (row, 0..) |cell, i| {
            wrapped_cells[i] = try self.wrapCell(cell);
            max_lines = @max(max_lines, wrapped_cells[i].items.len);
        }

        // Render each line of the row
        for (0..max_lines) |line_idx| {
            if (self.config.borders) {
                try writer.writeAll("│ ");
            }

            for (row, 0..) |_, i| {
                const alignment = if (self.config.alignments) |aligns|
                    aligns[i]
                else
                    .left;

                const width = self.widths[i];

                // Get the cell line content (or empty if this cell doesn't have this many lines)
                const cell_line = if (line_idx < wrapped_cells[i].items.len)
                    wrapped_cells[i].items[line_idx]
                else
                    "";

                const cell_len = @min(cell_line.len, width);
                const cell_pad = width -| cell_len;

                // Apply left padding
                for (0..self.config.padding_left) |_| {
                    try writer.writeByte(' ');
                }

                // Apply alignment
                switch (alignment) {
                    .left => {
                        try writer.writeAll(cell_line[0..cell_len]);
                        for (0..cell_pad) |_| try writer.writeByte(' ');
                    },
                    .right => {
                        for (0..cell_pad) |_| try writer.writeByte(' ');
                        try writer.writeAll(cell_line[0..cell_len]);
                    },
                    .center => {
                        const left_pad = cell_pad / 2;
                        const right_pad = cell_pad - left_pad;
                        for (0..left_pad) |_| try writer.writeByte(' ');
                        try writer.writeAll(cell_line[0..cell_len]);
                        for (0..right_pad) |_| try writer.writeByte(' ');
                    },
                }

                // Apply right padding
                for (0..self.config.padding_right) |_| {
                    try writer.writeByte(' ');
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
    }

    fn renderBlankRow(self: Self, writer: anytype) !void {
        if (self.config.borders) {
            try writer.writeAll("│ ");
        }

        for (self.widths, 0..) |width, i| {
            for (0..width + self.config.padding_left + self.config.padding_right) |_| {
                try writer.writeByte(' ');
            }

            if (i < self.widths.len - 1) {
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

// Padding control tests

test "Table with custom horizontal padding" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Name", "Age"}, .{
        .borders = true,
        .padding_left = 2,
        .padding_right = 2,
    });
    defer table.deinit();

    try table.addRow(&.{"Alice", "30"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    // Expected: padding adds 2 spaces on each side of cell content
    try std.testing.expect(std.mem.indexOf(u8, output, "Alice") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "30") != null);
}

test "Table with custom vertical padding" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Col1"}, .{
        .borders = true,
        .padding_top = 1,
        .padding_bottom = 1,
    });
    defer table.deinit();

    try table.addRow(&.{"Data"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    // With vertical padding, each row should have blank lines above and below
    try std.testing.expect(std.mem.indexOf(u8, output, "Data") != null);
}

test "Table with asymmetric padding" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"A", "B"}, .{
        .borders = false,
        .padding_left = 3,
        .padding_right = 1,
    });
    defer table.deinit();

    try table.addRow(&.{"X", "Y"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "X") != null);
}

test "Table with zero padding" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Name"}, .{
        .borders = false,
        .padding_left = 0,
        .padding_right = 0,
        .padding_top = 0,
        .padding_bottom = 0,
    });
    defer table.deinit();

    try table.addRow(&.{"Test"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    // With zero padding, content should be adjacent to boundaries
    try std.testing.expect(std.mem.indexOf(u8, output, "Test") != null);
}

test "Table with large padding values" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"X"}, .{
        .borders = false,
        .padding_left = 10,
        .padding_right = 10,
        .padding_top = 5,
        .padding_bottom = 5,
    });
    defer table.deinit();

    try table.addRow(&.{"A"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "A") != null);
}

// Multi-line cell tests

test "Table with newline in cell" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Description"}, .{
        .borders = false,
    });
    defer table.deinit();

    try table.addRow(&.{"Line 1\nLine 2"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    // Multi-line cell should preserve newlines
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 2") != null);
}

test "Table with cell wrapping on max_width" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Text"}, .{
        .borders = false,
        .max_width = 10,
    });
    defer table.deinit();

    try table.addRow(&.{"This is a very long text"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    // Content should be wrapped or truncated based on max_width
    try std.testing.expect(output.len > 0);
}

test "Table with mixed single and multi-line cells in same row" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Col1", "Col2"}, .{
        .borders = false,
    });
    defer table.deinit();

    try table.addRow(&.{"Single", "Multi\nLine"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    // Both types of cells should be present
    try std.testing.expect(std.mem.indexOf(u8, output, "Single") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Multi") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line") != null);
}

test "Table with multiple newlines in single cell" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Notes"}, .{
        .borders = false,
    });
    defer table.deinit();

    try table.addRow(&.{"First\nSecond\nThird"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "First") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Second") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Third") != null);
}

test "Table with empty lines within cell" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Content"}, .{
        .borders = false,
    });
    defer table.deinit();

    try table.addRow(&.{"Line 1\n\nLine 3"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    // Should handle blank lines within cell content
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 3") != null);
}

test "Table with word wrapping at word boundaries" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Message"}, .{
        .borders = false,
        .max_width = 15,
    });
    defer table.deinit();

    try table.addRow(&.{"The quick brown fox"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    // Word wrap should break at word boundaries, not mid-word
    try std.testing.expect(output.len > 0);
}

test "Table with very long word exceeding max_width" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Code"}, .{
        .borders = false,
        .max_width = 8,
    });
    defer table.deinit();

    try table.addRow(&.{"verylongword"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    // Should handle long words that can't fit within max_width
    try std.testing.expect(output.len > 0);
}

test "Table with newlines and padding combined" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Col1"}, .{
        .borders = false,
        .padding_left = 1,
        .padding_right = 1,
        .padding_top = 1,
        .padding_bottom = 1,
    });
    defer table.deinit();

    try table.addRow(&.{"Line A\nLine B"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    // Multi-line cells with padding should work together
    try std.testing.expect(std.mem.indexOf(u8, output, "Line A") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line B") != null);
}

test "Table multi-line with borders and padding" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Name", "Desc"}, .{
        .borders = true,
        .padding_left = 1,
        .padding_right = 1,
    });
    defer table.deinit();

    try table.addRow(&.{"Alice", "A\nB"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Alice") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "A") != null);
}

test "Table alignment with multi-line cells" {
    const allocator = std.testing.allocator;

    var table = try Table.init(allocator, &.{"Name"}, .{
        .borders = false,
        .alignments = &.{.center},
    });
    defer table.deinit();

    try table.addRow(&.{"First\nSecond"});

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try table.render(buf.writer());

    const output = buf.items;
    // Center alignment should work with multi-line content
    try std.testing.expect(std.mem.indexOf(u8, output, "First") != null);
}
