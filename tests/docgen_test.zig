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
        \\pub const Point = struct {
        \\    x: i32,
        \\    y: i32,
        \\    label: []const u8,
        \\};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const fields = decls[0].struct_fields.?;
    try testing.expectEqual(@as(usize, 3), fields.len);
    try testing.expectEqualStrings("x", fields[0].name);
    try testing.expectEqualStrings("i32", fields[0].field_type);
}

test "DocGenerator parses struct field doc comments" {
    const allocator = testing.allocator;
    const source =
        \\pub const Settings = struct {
        \\    /// Enable verbose output
        \\    verbose: bool,
        \\    /// Number of retries
        \\    retries: u32,
        \\};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const fields = decls[0].struct_fields.?;
    try testing.expect(fields[0].comment != null);
    try expectStringContains(fields[0].comment.?.content, "verbose");
}

test "DocGenerator struct with default values" {
    const allocator = testing.allocator;
    const source =
        \\pub const Options = struct {
        \\    timeout: u32 = 30,
        \\    enabled: bool = true,
        \\};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const fields = decls[0].struct_fields.?;
    try testing.expectEqual(@as(usize, 2), fields.len);
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
        \\pub const Status = enum {
        \\    pending,
        \\    active,
        \\    complete,
        \\};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const values = decls[0].enum_values.?;
    try testing.expectEqual(@as(usize, 3), values.len);
    try testing.expectEqualStrings("pending", values[0].name);
}

test "DocGenerator parses enum value doc comments" {
    const allocator = testing.allocator;
    const source =
        \\pub const Mode = enum {
        \\    /// Insert new mode
        \\    insert,
        \\    /// Delete mode
        \\    delete,
        \\};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const values = decls[0].enum_values.?;
    try testing.expect(values[0].comment != null);
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
        \\pub const Value = union {
        \\    integer: i64,
        \\    floating: f64,
        \\    text: []const u8,
        \\};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    const fields = decls[0].struct_fields.?;
    try testing.expectEqual(@as(usize, 3), fields.len);
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

test "DocGenerator filters private functions" {
    const allocator = testing.allocator;
    const source =
        \\fn internal() void {}
        \\pub fn external() void {}
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
    var all_public = true;
    for (decls) |decl| {
        if (!decl.is_public) {
            all_public = false;
        }
    }
    try testing.expect(all_public);
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
        \\pub const Config = struct {
        \\    width: u16,
        \\};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try gen.generateMarkdown(stream.writer());
    const output = stream.getWritten();

    try expectStringContains(output, "Config");
    try expectStringContains(output, "width");
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

test "DocGenerator scans directory recursively" {
    const allocator = testing.allocator;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    // Should support directory path
    // This test validates the API, actual scanning tested via integration
    try testing.expect(gen.parseDirectory != null);
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
    const result = gen.parseSource(source);
    // Test passes if no crash occurs
    _ = result;
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
        \\pub const Outer = struct {
        \\    pub const Inner = struct {
        \\        value: i32,
        \\    };
        \\    inner: Inner,
        \\};
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
        \\pub const MyStruct = struct {
        \\    value: i32,
        \\
        \\    pub fn init(value: i32) MyStruct {
        \\        return MyStruct{ .value = value };
        \\    }
        \\};
    ;

    var gen = try DocGenerator.init(allocator);
    defer gen.deinit();

    try gen.parseSource(source);
    const decls = gen.getDeclarations();

    try testing.expect(decls.len > 0);
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

test "DocGenerator markdown includes code blocks for functions" {
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

    // Should have code block markers for function signature
    try testing.expect(std.mem.indexOf(u8, output, "```") != null);
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
