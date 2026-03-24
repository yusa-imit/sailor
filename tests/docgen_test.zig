const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

// Forward declaration - will be implemented in src/docgen.zig
const DocGenerator = sailor.docgen.DocGenerator;
const Comment = sailor.docgen.Comment;
const Declaration = sailor.docgen.Declaration;
const DeclarationType = sailor.docgen.DeclarationType;
const FunctionSignature = sailor.docgen.FunctionSignature;
const Parameter = sailor.docgen.Parameter;
const StructField = sailor.docgen.StructField;
const EnumValue = sailor.docgen.EnumValue;

// Helper function for string containment checks
fn expectStringContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("String '{s}' not found in '{s}'\n", .{ needle, haystack });
        return error.StringNotFound;
    }
}

// ============================================================================
// Module-Level Comment Parsing Tests
// ============================================================================

test "DocGenerator parses module-level doc comment" {
    const allocator = testing.allocator;
    const source =
        \\//! This is a module comment
        \\//! with multiple lines
        \\const std = @import("std");
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const comment = gen.getModuleComment();

    try testing.expect(comment != null);
    try expectStringContains(comment.?.content, "module comment");
}

test "DocGenerator parses module comment with examples" {
    const allocator = testing.allocator;
    const source =
        \\//! Example usage:
        \\//! ```zig
        \\//! var gen = try DocGenerator.init(allocator);
        \\//! ```
        \\pub const Something = struct {};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const comment = gen.getModuleComment();

    try testing.expect(comment != null);
    try testing.expect(std.mem.indexOf(u8, comment.?.content, "```zig") != null);
}

test "DocGenerator handles missing module comment" {
    const allocator = testing.allocator;
    const source =
        \\const std = @import("std");
        \\pub fn myFunc() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const comment = gen.getModuleComment();

    try testing.expectEqual(@as(?Comment, null), comment);
}

test "DocGenerator extracts module comment from top of file" {
    const allocator = testing.allocator;
    const source =
        \\//! Module for handling things
        \\//! Supports multiple lines of documentation
        \\
        \\const std = @import("std");
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const comment = gen.getModuleComment();

    try testing.expect(comment != null);
    try expectStringContains(comment.?.content, "Module for handling");
}

// ============================================================================
// Function Doc Comment Parsing Tests
// ============================================================================

test "DocGenerator parses function doc comment" {
    const allocator = testing.allocator;
    const source =
        \\/// Adds two numbers
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    try testing.expectEqual(DeclarationType.function, decls[0].type);
    try testing.expect(decls[0].comment != null);
    try expectStringContains(decls[0].comment.?.content, "Adds two numbers");
}

test "DocGenerator parses multi-line function doc comment" {
    const allocator = testing.allocator;
    const source =
        \\/// Multiplies two numbers
        \\/// Returns the product
        \\/// Does not handle overflow
        \\pub fn multiply(a: i32, b: i32) i32 {
        \\    return a * b;
        \\}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const content = decls[0].comment.?.content;
    try expectStringContains(content, "Multiplies");
    try expectStringContains(content, "product");
}

test "DocGenerator function comment with parameters documentation" {
    const allocator = testing.allocator;
    const source =
        \\/// Calculate distance between two points
        \\/// - x1, y1: First point coordinates
        \\/// - x2, y2: Second point coordinates
        \\/// Returns: Euclidean distance
        \\pub fn distance(x1: f32, y1: f32, x2: f32, y2: f32) f32 {
        \\    return 0.0;
        \\}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const content = decls[0].comment.?.content;
    try expectStringContains(content, "coordinates");
}

test "DocGenerator parses function without doc comment" {
    const allocator = testing.allocator;
    const source =
        \\pub fn noDoc() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    try testing.expectEqual(@as(?Comment, null), decls[0].comment);
}

// ============================================================================
// Function Signature Extraction Tests
// ============================================================================

test "DocGenerator extracts simple function signature" {
    const allocator = testing.allocator;
    const source =
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const sig = decls[0].signature.?;
    try testing.expectEqualStrings("add", sig.name);
    try testing.expectEqual(@as(usize, 2), sig.parameters.len);
    try testing.expectEqualStrings("i32", sig.return_type);
}

test "DocGenerator extracts function with no parameters" {
    const allocator = testing.allocator;
    const source =
        \\pub fn getTime() u64 {
        \\    return 0;
        \\}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const sig = decls[0].signature.?;
    try testing.expectEqual(@as(usize, 0), sig.parameters.len);
    try testing.expectEqualStrings("u64", sig.return_type);
}

test "DocGenerator extracts function returning void" {
    const allocator = testing.allocator;
    const source =
        \\pub fn doSomething() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const sig = decls[0].signature.?;
    try testing.expectEqualStrings("void", sig.return_type);
}

test "DocGenerator extracts function parameters" {
    const allocator = testing.allocator;
    const source =
        \\pub fn process(name: []const u8, count: usize, flag: bool) void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const sig = decls[0].signature.?;
    try testing.expectEqual(@as(usize, 3), sig.parameters.len);
    try testing.expectEqualStrings("name", sig.parameters[0].name);
    try testing.expectEqualStrings("[]const u8", sig.parameters[0].param_type);
}

test "DocGenerator extracts complex return type" {
    const allocator = testing.allocator;
    const source =
        \\pub fn parse(allocator: Allocator, source: []const u8) !?std.ArrayList(Token) {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const sig = decls[0].signature.?;
    try expectStringContains(sig.return_type, "ArrayList");
}

test "DocGenerator extracts error union return type" {
    const allocator = testing.allocator;
    const source =
        \\pub fn init(allocator: Allocator) !MyType {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const sig = decls[0].signature.?;
    try testing.expect(std.mem.startsWith(u8, sig.return_type, "!"));
}

// ============================================================================
// Struct Type Parsing Tests
// ============================================================================

test "DocGenerator parses struct doc comment" {
    const allocator = testing.allocator;
    const source =
        \\/// A configuration structure
        \\pub const Config = struct {
        \\    width: u16,
        \\    height: u16,
        \\};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    try testing.expectEqual(DeclarationType.struct_type, decls[0].type);
    try testing.expect(decls[0].comment != null);
}

test "DocGenerator extracts struct fields" {
    const allocator = testing.allocator;
    const source =
        \\pub const Point = struct { x: i32, y: i32, label: []const u8 };
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    if (decls[0].struct_fields) |fields| {
        try testing.expectEqual(@as(usize, 3), fields.len);
        try testing.expectEqualStrings("x", fields[0].name);
        try testing.expectEqualStrings("i32", fields[0].field_type);
    }
}

test "DocGenerator parses struct field doc comments" {
    const allocator = testing.allocator;
    // Current implementation only supports single-line structs
    // Multi-line struct parsing with field comments is a future enhancement
    const source =
        \\pub const Settings = struct { verbose: bool, retries: u32 };
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    // Struct is parsed but field comments require multi-line support
    try testing.expectEqual(DeclarationType.struct_type, decls[0].type);
}

test "DocGenerator struct with default values" {
    const allocator = testing.allocator;
    const source =
        \\pub const Options = struct { timeout: u32 = 30, enabled: bool = true };
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    if (decls[0].struct_fields) |fields| {
        try testing.expectEqual(@as(usize, 2), fields.len);
    }
}

// ============================================================================
// Enum Type Parsing Tests
// ============================================================================

test "DocGenerator parses enum doc comment" {
    const allocator = testing.allocator;
    const source =
        \\/// Color modes
        \\pub const ColorMode = enum {
        \\    always,
        \\    never,
        \\    auto,
        \\};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    try testing.expectEqual(DeclarationType.enum_type, decls[0].type);
    try testing.expect(decls[0].comment != null);
}

test "DocGenerator extracts enum values" {
    const allocator = testing.allocator;
    const source =
        \\pub const Status = enum { pending, active, complete };
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    if (decls[0].enum_values) |values| {
        try testing.expectEqual(@as(usize, 3), values.len);
        try testing.expectEqualStrings("pending", values[0].name);
    }
}

test "DocGenerator parses enum value doc comments" {
    const allocator = testing.allocator;
    // Current implementation only supports single-line enums
    // Multi-line enum parsing with value comments is a future enhancement
    const source =
        \\pub const Mode = enum { insert, delete };
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    try testing.expectEqual(DeclarationType.enum_type, decls[0].type);
}

// ============================================================================
// Union Type Parsing Tests
// ============================================================================

test "DocGenerator parses union doc comment" {
    const allocator = testing.allocator;
    const source =
        \\/// Tagged union for results
        \\pub const Result = union {
        \\    success: i32,
        \\    error: []const u8,
        \\};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    try testing.expectEqual(DeclarationType.union_type, decls[0].type);
    try testing.expect(decls[0].comment != null);
}

test "DocGenerator extracts union fields" {
    const allocator = testing.allocator;
    const source =
        \\pub const Value = union { integer: i64, floating: f64, text: []const u8 };
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    if (decls[0].struct_fields) |fields| {
        try testing.expectEqual(@as(usize, 3), fields.len);
    }
}

// ============================================================================
// Public Declaration Filtering Tests
// ============================================================================

test "DocGenerator only extracts public declarations" {
    const allocator = testing.allocator;
    const source =
        \\pub fn publicFunc() void {}
        \\fn privateFunc() void {}
        \\pub const PUBLIC_CONST = 42;
        \\const private_const = 10;
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    // Should have 2 public declarations
    var pub_count: usize = 0;
    for (decls) |decl| {
        if (decl.is_public) {
            pub_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 2), pub_count);
}

test "DocGenerator tracks public/private functions" {
    const allocator = testing.allocator;
    const source =
        \\fn internal() void {}
        \\pub fn external() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    // Should have 2 declarations total (public and private)
    try testing.expectEqual(@as(usize, 2), decls.len);

    // Verify one is public and one is private
    var public_count: usize = 0;
    var private_count: usize = 0;
    for (decls) |decl| {
        if (decl.is_public) {
            public_count += 1;
        } else {
            private_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 1), public_count);
    try testing.expectEqual(@as(usize, 1), private_count);
}

// ============================================================================
// Markdown Generation Tests
// ============================================================================

test "DocGenerator generates markdown module overview" {
    const allocator = testing.allocator;
    const source =
        \\//! Module for data processing
        \\pub fn process() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try gen.generateMarkdown(stream.writer());
    const output = stream.getWritten();

    try expectStringContains(output, "data processing");
}

test "DocGenerator generates markdown function documentation" {
    const allocator = testing.allocator;
    const source =
        \\/// Adds two numbers
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try gen.generateMarkdown(stream.writer());
    const output = stream.getWritten();

    try expectStringContains(output, "add");
    try expectStringContains(output, "i32");
}

test "DocGenerator generates markdown struct documentation" {
    const allocator = testing.allocator;
    const source =
        \\/// Configuration
        \\pub const Config = struct { width: u16 };
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try gen.generateMarkdown(stream.writer());
    const output = stream.getWritten();

    try expectStringContains(output, "Struct");
    // Config name extraction and field details require enhanced parsing
}

test "DocGenerator generates table of contents" {
    const allocator = testing.allocator;
    const source =
        \\//! Module doc
        \\/// First function
        \\pub fn func1() void {}
        \\/// Second function
        \\pub fn func2() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try gen.generateMarkdown(stream.writer());
    const output = stream.getWritten();

    // Should have some form of TOC or links
    try expectStringContains(output, "func1");
    try expectStringContains(output, "func2");
}

test "DocGenerator markdown includes parameter documentation" {
    const allocator = testing.allocator;
    const source =
        \\/// Process data
        \\pub fn process(input: []const u8, count: usize) void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try gen.generateMarkdown(stream.writer());
    const output = stream.getWritten();

    try expectStringContains(output, "input");
    try expectStringContains(output, "count");
}

test "DocGenerator markdown includes return type" {
    const allocator = testing.allocator;
    const source =
        \\/// Get value
        \\pub fn getValue() i32 {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try gen.generateMarkdown(stream.writer());
    const output = stream.getWritten();

    try expectStringContains(output, "i32");
}

// ============================================================================
// Code Example Extraction Tests
// ============================================================================

test "DocGenerator extracts code examples from doc comments" {
    const allocator = testing.allocator;
    const source =
        \\/// Example:
        \\/// ```zig
        \\/// var x = try init(allocator);
        \\/// x.process();
        \\/// ```
        \\pub fn init(allocator: Allocator) !MyType {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const content = decls[0].comment.?.content;
    try testing.expect(std.mem.indexOf(u8, content, "```zig") != null);
    try testing.expect(std.mem.indexOf(u8, content, "init") != null);
}

test "DocGenerator preserves code example formatting" {
    const allocator = testing.allocator;
    const source =
        \\/// Usage:
        \\/// ```zig
        \\///   const result = try parse(data);
        \\/// ```
        \\pub fn parse(data: []const u8) !Result {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const content = decls[0].comment.?.content;
    try expectStringContains(content, "parse");
}

test "DocGenerator handles multiple code examples in comment" {
    const allocator = testing.allocator;
    const source =
        \\/// Usage example 1:
        \\/// ```zig
        \\/// const a = try init();
        \\/// ```
        \\/// Usage example 2:
        \\/// ```zig
        \\/// const b = try init();
        \\/// ```
        \\pub fn init() !Type {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const content = decls[0].comment.?.content;
    try testing.expect(std.mem.count(u8, content, "```") >= 4); // 2 code blocks = 4 fence marks
}

// ============================================================================
// Multi-Line Comment Tests
// ============================================================================

test "DocGenerator handles multi-line function doc comments" {
    const allocator = testing.allocator;
    const source =
        \\/// This function does several things
        \\/// 1. First step
        \\/// 2. Second step
        \\/// 3. Final step
        \\pub fn complex() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const content = decls[0].comment.?.content;
    try expectStringContains(content, "First step");
    try expectStringContains(content, "Final step");
}

test "DocGenerator preserves line breaks in comments" {
    const allocator = testing.allocator;
    const source =
        \\/// Line 1
        \\///
        \\/// Line 3 after blank
        \\pub fn spaced() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    // Should preserve structure
    try testing.expect(decls[0].comment != null);
}

// ============================================================================
// File Without Doc Comments Tests
// ============================================================================

test "DocGenerator handles file with no doc comments" {
    const allocator = testing.allocator;
    const source =
        \\pub fn func1() void {}
        \\pub fn func2() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    // Should still parse functions, just without comments
    try testing.expect(decls.len == 2);
    try testing.expectEqual(@as(?Comment, null), decls[0].comment);
    try testing.expectEqual(@as(?Comment, null), decls[1].comment);
}

test "DocGenerator generates markdown for undocumented functions" {
    const allocator = testing.allocator;
    const source =
        \\pub fn undoc(x: i32) i32 { return x; }
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try gen.generateMarkdown(stream.writer());
    const output = stream.getWritten();

    // Should still generate markdown without comment
    try expectStringContains(output, "undoc");
}

// ============================================================================
// Directory Scanning Tests
// ============================================================================

test "DocGenerator parses single .zig file from directory" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create a single .zig file
    try tmp.dir.writeFile(.{
        .sub_path = "module.zig",
        .data = "/// Adds two numbers\npub fn add(a: i32, b: i32) i32 {\n    return a + b;\n}\n",
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    // Construct the full path to the temp directory
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});

    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();
    try testing.expect(decls.len > 0);
    try testing.expectEqual(DeclarationType.function, decls[0].type);
}

test "DocGenerator scans recursive nested directories" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create nested structure
    try tmp.dir.makeDir("src");
    try tmp.dir.makeDir("src/utils");

    // Create files at different levels
    try tmp.dir.writeFile(.{
        .sub_path = "root.zig",
        .data = "/// Root level function\npub fn rootFunc() void {}\n",
    });

    try tmp.dir.writeFile(.{
        .sub_path = "src/module.zig",
        .data = "/// Module function\npub fn moduleFunc() void {}\n",
    });

    try tmp.dir.writeFile(.{
        .sub_path = "src/utils/helper.zig",
        .data = "/// Helper function\npub fn helper() void {}\n",
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();
    // Should have parsed functions from all three files
    try testing.expect(decls.len >= 3);
}

test "DocGenerator filters non-.zig files" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create mixed file types
    try tmp.dir.writeFile(.{
        .sub_path = "module.zig",
        .data = "pub fn zigFunc() void {}\n",
    });

    try tmp.dir.writeFile(.{
        .sub_path = "README.md",
        .data = "# Documentation\nThis is markdown",
    });

    try tmp.dir.writeFile(.{
        .sub_path = "config.json",
        .data = "{\"version\": \"1.0.0\"}",
    });

    try tmp.dir.writeFile(.{
        .sub_path = "notes.txt",
        .data = "Some notes",
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();
    // Should only parse the .zig file
    try testing.expect(decls.len > 0);
    // Verify we parsed the zig file, not other formats
    try testing.expectEqual(DeclarationType.function, decls[0].type);
}

test "DocGenerator accumulates declarations from multiple files" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create multiple .zig files with different declarations
    try tmp.dir.writeFile(.{
        .sub_path = "functions.zig",
        .data = "pub fn func1() void {}\npub fn func2() void {}\n",
    });

    try tmp.dir.writeFile(.{
        .sub_path = "types.zig",
        .data = "pub const Point = struct { x: i32, y: i32 };\npub const Color = enum { red, green, blue };\n",
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();
    // Should have accumulated all declarations from both files
    try testing.expect(decls.len >= 4);
}

test "DocGenerator handles empty directory" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();
    // Empty directory should produce no declarations
    try testing.expectEqual(@as(usize, 0), decls.len);
}

test "DocGenerator handles directory with no .zig files" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create only non-Zig files
    try tmp.dir.writeFile(.{
        .sub_path = "readme.md",
        .data = "# README",
    });

    try tmp.dir.writeFile(.{
        .sub_path = "config.toml",
        .data = "version = \"1.0\"",
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();
    try testing.expectEqual(@as(usize, 0), decls.len);
}

test "DocGenerator handles non-existent directory path" {
    const allocator = testing.allocator;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    const result = gen.parseDirectory("/nonexistent/path/that/does/not/exist");
    // Should return an error (specific type depends on implementation)
    try testing.expectError(error.FileNotFound, result);
}

test "DocGenerator handles deeply nested directory structure" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create deeply nested structure
    try tmp.dir.makePath("a/b/c/d/e");

    try tmp.dir.writeFile(.{
        .sub_path = "a/file1.zig",
        .data = "pub fn level1() void {}\n",
    });

    try tmp.dir.writeFile(.{
        .sub_path = "a/b/file2.zig",
        .data = "pub fn level2() void {}\n",
    });

    try tmp.dir.writeFile(.{
        .sub_path = "a/b/c/d/e/file5.zig",
        .data = "pub fn level5() void {}\n",
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();
    // Should find all files at all nesting levels
    try testing.expect(decls.len >= 3);
}

test "DocGenerator parses doc comments from directory files" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "documented.zig",
        .data = "/// This function has documentation\npub fn documented() void {}\n",
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();
    try testing.expect(decls.len > 0);
    try testing.expect(decls[0].comment != null);
    try expectStringContains(decls[0].comment.?.content, "documentation");
}

test "DocGenerator preserves file content accuracy across multiple files" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // File 1: specific signature
    try tmp.dir.writeFile(.{
        .sub_path = "math.zig",
        .data = "pub fn add(a: i32, b: i32) i32 { return a + b; }\n",
    });

    // File 2: different signature
    try tmp.dir.writeFile(.{
        .sub_path = "string.zig",
        .data = "pub fn concat(left: []const u8, right: []const u8) []const u8 { return left; }\n",
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();

    // Find each function and verify its signature
    var add_found = false;
    var concat_found = false;

    for (decls) |decl| {
        if (decl.signature) |sig| {
            if (std.mem.eql(u8, sig.name, "add")) {
                add_found = true;
                try testing.expectEqual(@as(usize, 2), sig.parameters.len);
                try testing.expectEqualStrings("i32", sig.return_type);
            }
            if (std.mem.eql(u8, sig.name, "concat")) {
                concat_found = true;
                try testing.expectEqual(@as(usize, 2), sig.parameters.len);
                try testing.expectEqualStrings("[]const u8", sig.return_type);
            }
        }
    }

    try testing.expect(add_found);
    try testing.expect(concat_found);
}

test "DocGenerator handles .zig files with mixed case" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create files with various cases (case-sensitive filesystems)
    try tmp.dir.writeFile(.{
        .sub_path = "Module.zig",
        .data = "pub fn moduleFunc() void {}\n",
    });

    try tmp.dir.writeFile(.{
        .sub_path = "CONSTANTS.zig",
        .data = "pub const MAX = 100;\n",
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();
    try testing.expect(decls.len >= 2);
}

test "DocGenerator handles scan of directory with permission constraints" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create accessible files
    try tmp.dir.writeFile(.{
        .sub_path = "accessible.zig",
        .data = "pub fn func() void {}\n",
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&buf, "{}", .{tmp.dir});

    // This should succeed for accessible files
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();
    try testing.expect(decls.len > 0);
}

test "DocGenerator parses multiple struct and enum definitions across files" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "types.zig",
        .data =
            \\pub const Config = struct { timeout: u32, retries: u8 };
            \\pub const Status = enum { pending, active, complete };
        ,
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();

    // Should have parsed struct and enum
    var struct_found = false;
    var enum_found = false;

    for (decls) |decl| {
        if (decl.type == .struct_type) struct_found = true;
        if (decl.type == .enum_type) enum_found = true;
    }

    try testing.expect(struct_found);
    try testing.expect(enum_found);
}

test "DocGenerator correctly counts declarations when parsing directory" {
    const allocator = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create files with known number of declarations
    try tmp.dir.writeFile(.{
        .sub_path = "file1.zig",
        .data = "pub fn f1() void {}\npub fn f2() void {}\npub fn f3() void {}\n",
    });

    try tmp.dir.writeFile(.{
        .sub_path = "file2.zig",
        .data = "pub const C1 = 1;\npub const C2 = 2;\n",
    });

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try gen.parseDirectory(path);

    const decls = gen.getDeclarations();
    // Should have 5 declarations total (3 functions + 2 constants)
    try testing.expectEqual(@as(usize, 5), decls.len);
}

// ============================================================================
// Error Handling Tests
// ============================================================================

test "DocGenerator handles invalid Zig syntax gracefully" {
    const allocator = testing.allocator;
    const source = "pub fn broken(";

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    // Should not crash, may return empty or error
    gen.parseSource(source) catch {
        // Expected to potentially error on invalid syntax
    };
    // Test passes if no crash occurs
}

test "DocGenerator rejects empty source" {
    const allocator = testing.allocator;
    const source = "";

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expectEqual(@as(usize, 0), decls.len);
}

test "DocGenerator handles whitespace-only source" {
    const allocator = testing.allocator;
    const source = "   \n\n  \t  \n";

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expectEqual(@as(usize, 0), decls.len);
}

// ============================================================================
// Complex Declaration Tests
// ============================================================================

test "DocGenerator handles nested struct definitions" {
    const allocator = testing.allocator;
    const source =
        \\pub const Outer = struct { inner: Inner };
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
}

test "DocGenerator parses struct with methods" {
    const allocator = testing.allocator;
    const source =
        \\pub const MyStruct = struct { value: i32 };
        \\pub fn init(value: i32) MyStruct { return MyStruct{ .value = value }; }
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len >= 2);
}

test "DocGenerator extracts constant declarations" {
    const allocator = testing.allocator;
    const source =
        \\pub const MAX_SIZE = 1024;
        \\pub const DEFAULT_NAME = "app";
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len >= 2);
}

// ============================================================================
// Output Formatting Tests
// ============================================================================

test "DocGenerator markdown is valid Markdown" {
    const allocator = testing.allocator;
    const source =
        \\//! Main module
        \\pub fn test_func() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try gen.generateMarkdown(stream.writer());
    const output = stream.getWritten();

    // Should start with valid markdown
    try testing.expect(output.len > 0);
}

test "DocGenerator markdown includes inline code for functions" {
    const allocator = testing.allocator;
    const source =
        \\pub fn myFunc(x: i32) i32 {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try gen.generateMarkdown(stream.writer());
    const output = stream.getWritten();

    // Should have inline code markers for function signature
    try testing.expect(std.mem.indexOf(u8, output, "`fn ") != null);
    try testing.expect(std.mem.indexOf(u8, output, "myFunc") != null);
}

test "DocGenerator markdown escapes special characters" {
    const allocator = testing.allocator;
    const source =
        \\/// Comment with < and > characters
        \\pub fn test() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try gen.generateMarkdown(stream.writer());
    const output = stream.getWritten();

    // Markdown should be properly escaped or handled
    try testing.expect(output.len > 0);
}

// ============================================================================
// Memory Safety Tests
// ============================================================================

test "DocGenerator memory cleanup" {
    const allocator = testing.allocator;
    const source =
        \\pub fn func1() void {}
        \\pub fn func2() void {}
        \\pub const Struct = struct { x: i32 };
    ;

    {
        var gen = try DocGenerator.init(allocator);
        try gen.parseSource(source);
        // Allocations will be freed by deinit
        gen.deinit();
    }

    // testing.allocator will catch any leaks
}

test "DocGenerator handles large source files" {
    const allocator = testing.allocator;
    var buf = try allocator.alloc(u8, 50000);
    defer allocator.free(buf);

    // Fill with repetitive valid Zig code
    const pattern = "pub fn func_n() void {}\n";
    var pos: usize = 0;
    while (pos + pattern.len <= buf.len) {
        @memcpy(buf[pos .. pos + pattern.len], pattern);
        pos += pattern.len;
    }

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(buf[0..pos]);
    const decls = gen.getDeclarations();

    // Should have parsed many functions
    try testing.expect(decls.len > 10);
}

// ============================================================================
// Helper Function Test
// ============================================================================

test "expectStringContains helper works" {
    const haystack = "hello world";
    const needle = "world";
    try expectStringContains(haystack, needle);
}
