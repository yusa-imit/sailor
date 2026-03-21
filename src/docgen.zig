//! Documentation generator for Zig source files
//!
//! Parses Zig source code to extract:
//! - Module-level doc comments (//!)
//! - Declaration doc comments (///)
//! - Function signatures with parameters and return types
//! - Type definitions (struct, enum, union)
//! - Public declarations only
//!
//! Generates markdown documentation with:
//! - Module overview
//! - Table of contents
//! - Type documentation with fields
//! - Function documentation with parameters and return types
//! - Code examples from doc comments

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Represents a documentation comment
pub const Comment = struct {
    /// Raw comment content (without leading //, ///, //!)
    content: []const u8,
};

/// Type of declaration
pub const DeclarationType = enum {
    function,
    struct_type,
    enum_type,
    union_type,
    constant,
};

/// Function parameter
pub const Parameter = struct {
    name: []const u8,
    param_type: []const u8,
};

/// Function signature
pub const FunctionSignature = struct {
    name: []const u8,
    parameters: []const Parameter,
    return_type: []const u8,
};

/// Struct field
pub const StructField = struct {
    name: []const u8,
    field_type: []const u8,
    comment: ?Comment = null,
};

/// Enum value
pub const EnumValue = struct {
    name: []const u8,
    comment: ?Comment = null,
};

/// Declaration in the source file
pub const Declaration = struct {
    type: DeclarationType,
    is_public: bool,
    comment: ?Comment = null,
    signature: ?FunctionSignature = null,
    struct_fields: ?[]const StructField = null,
    enum_values: ?[]const EnumValue = null,
};

/// Documentation generator
pub const DocGenerator = struct {
    allocator: Allocator,
    declarations: std.ArrayListUnmanaged(Declaration) = .{},
    module_comment: ?Comment = null,

    const Self = @This();

    /// Initialize a new documentation generator
    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        // Free all declaration data
        for (self.declarations.items) |decl| {
            if (decl.comment) |c| {
                self.allocator.free(c.content);
            }
            if (decl.signature) |sig| {
                self.allocator.free(sig.name);
                self.allocator.free(sig.return_type);
                for (sig.parameters) |param| {
                    self.allocator.free(param.name);
                    self.allocator.free(param.param_type);
                }
                self.allocator.free(sig.parameters);
            }
            if (decl.struct_fields) |fields| {
                for (fields) |field| {
                    self.allocator.free(field.name);
                    self.allocator.free(field.field_type);
                    if (field.comment) |c| {
                        self.allocator.free(c.content);
                    }
                }
                self.allocator.free(fields);
            }
            if (decl.enum_values) |values| {
                for (values) |val| {
                    self.allocator.free(val.name);
                    if (val.comment) |c| {
                        self.allocator.free(c.content);
                    }
                }
                self.allocator.free(values);
            }
        }
        self.declarations.deinit(self.allocator);

        if (self.module_comment) |c| {
            self.allocator.free(c.content);
        }
    }

    /// Parse Zig source code
    pub fn parseSource(self: *Self, source: []const u8) !void {
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_idx: usize = 0;
        var pending_comment: ?[]const u8 = null;
        var module_lines: std.ArrayListUnmanaged([]const u8) = .{};
        defer module_lines.deinit(self.allocator);

        while (lines.next()) |line| : (line_idx += 1) {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            // Handle module-level doc comments (//!)
            if (std.mem.startsWith(u8, trimmed, "//!")) {
                const comment_content = trimmed[3..];
                const trimmed_content = std.mem.trim(u8, comment_content, " \t");
                try module_lines.append(self.allocator, trimmed_content);
                continue;
            }

            // If we see a non-comment line after module comments, save module comment
            if (module_lines.items.len > 0 and !std.mem.startsWith(u8, trimmed, "//!")) {
                if (self.module_comment == null) {
                    const joined = try std.mem.join(self.allocator, "\n", module_lines.items);
                    self.module_comment = Comment{ .content = joined };
                }
                module_lines.clearRetainingCapacity();
            }

            // Handle declaration comments (///)
            if (std.mem.startsWith(u8, trimmed, "///")) {
                const comment_content = trimmed[3..];
                const trimmed_content = std.mem.trim(u8, comment_content, " \t");
                if (pending_comment) |pc| {
                    const combined = try std.mem.concat(self.allocator, u8, &[_][]const u8{ pc, "\n", trimmed_content });
                    self.allocator.free(pc);
                    pending_comment = combined;
                } else {
                    pending_comment = try self.allocator.dupe(u8, trimmed_content);
                }
                continue;
            }

            // Skip empty lines and comments that don't match our patterns
            if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//")) {
                continue;
            }

            // Parse declaration line
            if (std.mem.indexOf(u8, trimmed, "fn ") != null or
                std.mem.indexOf(u8, trimmed, "const ") != null or
                std.mem.indexOf(u8, trimmed, "var ") != null)
            {
                try self.parseDeclaration(trimmed, pending_comment);
                if (pending_comment) |pc| {
                    self.allocator.free(pc);
                    pending_comment = null;
                }
            }
        }
    }

    fn parseDeclaration(self: *Self, line: []const u8, comment: ?[]const u8) !void {
        const is_public = std.mem.indexOf(u8, line, "pub ") != null;

        if (std.mem.indexOf(u8, line, "fn ") != null) {
            try self.parseFunctionDeclaration(line, comment, is_public);
        } else if (std.mem.indexOf(u8, line, "struct") != null) {
            // For now, just extract basic struct info
            try self.parseStructDeclaration(line, comment, is_public);
        } else if (std.mem.indexOf(u8, line, "enum") != null) {
            try self.parseEnumDeclaration(line, comment, is_public);
        } else if (std.mem.indexOf(u8, line, "union") != null) {
            try self.parseUnionDeclaration(line, comment, is_public);
        } else if (std.mem.indexOf(u8, line, "const ") != null or std.mem.indexOf(u8, line, "var ") != null) {
            try self.parseConstantDeclaration(line, comment, is_public);
        }
    }

    fn parseFunctionDeclaration(self: *Self, line: []const u8, comment: ?[]const u8, is_public: bool) !void {
        const fn_idx = std.mem.indexOf(u8, line, "fn ") orelse return;
        const fn_part = line[fn_idx + 3 ..];

        // Extract function name
        const paren_idx = std.mem.indexOf(u8, fn_part, "(") orelse return;
        const func_name = std.mem.trim(u8, fn_part[0..paren_idx], " \t");

        // Find matching closing paren
        var paren_depth: i32 = 1;
        var close_paren_idx: usize = paren_idx + 1;
        while (close_paren_idx < fn_part.len and paren_depth > 0) {
            if (fn_part[close_paren_idx] == '(') {
                paren_depth += 1;
            } else if (fn_part[close_paren_idx] == ')') {
                paren_depth -= 1;
            }
            close_paren_idx += 1;
        }

        // Extract parameters
        const params_str = fn_part[paren_idx + 1 .. close_paren_idx - 1];
        var parameters = std.ArrayListUnmanaged(Parameter){};
        defer parameters.deinit(self.allocator);

        if (params_str.len > 0) {
            var params = std.mem.splitScalar(u8, params_str, ',');
            while (params.next()) |param_str| {
                const p = std.mem.trim(u8, param_str, " \t");
                if (p.len == 0) continue;

                if (std.mem.indexOf(u8, p, ":")) |colon_idx| {
                    const param_name = std.mem.trim(u8, p[0..colon_idx], " \t");
                    const param_type = std.mem.trim(u8, p[colon_idx + 1 ..], " \t");

                    try parameters.append(self.allocator, Parameter{
                        .name = try self.allocator.dupe(u8, param_name),
                        .param_type = try self.allocator.dupe(u8, param_type),
                    });
                }
            }
        }

        // Extract return type
        const after_paren = fn_part[close_paren_idx..];
        var return_type: []const u8 = "void";
        if (std.mem.indexOf(u8, after_paren, "{")) |brace_idx| {
            const ret_str = std.mem.trim(u8, after_paren[0..brace_idx], " \t");
            if (ret_str.len > 0) {
                return_type = ret_str;
            }
        } else if (after_paren.len > 0) {
            return_type = std.mem.trim(u8, after_paren, " \t\r\n;");
        }

        const return_type_copy = try self.allocator.dupe(u8, return_type);
        const name_copy = try self.allocator.dupe(u8, func_name);

        try self.declarations.append(self.allocator, Declaration{
            .type = .function,
            .is_public = is_public,
            .comment = if (comment) |c| Comment{ .content = c } else null,
            .signature = FunctionSignature{
                .name = name_copy,
                .parameters = try self.allocator.dupe(Parameter, parameters.items),
                .return_type = return_type_copy,
            },
        });
    }

    fn parseStructDeclaration(self: *Self, line: []const u8, comment: ?[]const u8, is_public: bool) !void {
        // Extract struct name
        const const_idx = std.mem.indexOf(u8, line, "const ") orelse return;
        const struct_part = line[const_idx + 6 ..];
        const eq_idx = std.mem.indexOf(u8, struct_part, "=") orelse return;
        _ = std.mem.trim(u8, struct_part[0..eq_idx], " \t");

        // For now, create struct declaration without field details (full parsing requires multi-line)
        var fields = std.ArrayListUnmanaged(StructField){};

        // Try to extract basic field info from same line
        if (std.mem.indexOf(u8, line, "struct")) |struct_idx| {
            const after_struct = line[struct_idx + 6 ..];
            if (std.mem.indexOf(u8, after_struct, "{")) |open_brace| {
                const brace_content = after_struct[open_brace + 1 ..];
                if (std.mem.indexOf(u8, brace_content, "}")) |close_brace| {
                    const field_str = brace_content[0..close_brace];
                    var field_split = std.mem.splitScalar(u8, field_str, ',');
                    while (field_split.next()) |field_decl| {
                        const f = std.mem.trim(u8, field_decl, " \t\r\n");
                        if (f.len == 0) continue;

                        if (std.mem.indexOf(u8, f, ":")) |colon_idx| {
                            const fname = std.mem.trim(u8, f[0..colon_idx], " \t");
                            const ftype_part = f[colon_idx + 1 ..];
                            const ftype = std.mem.trim(u8, ftype_part, " \t=0123456789;");

                            try fields.append(self.allocator, StructField{
                                .name = try self.allocator.dupe(u8, fname),
                                .field_type = try self.allocator.dupe(u8, ftype),
                            });
                        }
                    }
                }
            }
        }

        try self.declarations.append(self.allocator, Declaration{
            .type = .struct_type,
            .is_public = is_public,
            .comment = if (comment) |c| Comment{ .content = c } else null,
            .struct_fields = if (fields.items.len > 0) try self.allocator.dupe(StructField, fields.items) else null,
        });

        fields.deinit(self.allocator);
    }

    fn parseEnumDeclaration(self: *Self, line: []const u8, comment: ?[]const u8, is_public: bool) !void {
        const const_idx = std.mem.indexOf(u8, line, "const ") orelse return;
        const enum_part = line[const_idx + 6 ..];
        const eq_idx = std.mem.indexOf(u8, enum_part, "=") orelse return;
        _ = std.mem.trim(u8, enum_part[0..eq_idx], " \t");

        var values = std.ArrayListUnmanaged(EnumValue){};
        defer values.deinit(self.allocator);

        // Try to extract values from same line
        if (std.mem.indexOf(u8, line, "enum")) |enum_idx| {
            const after_enum = line[enum_idx + 4 ..];
            if (std.mem.indexOf(u8, after_enum, "{")) |open_brace| {
                const brace_content = after_enum[open_brace + 1 ..];
                if (std.mem.indexOf(u8, brace_content, "}")) |close_brace| {
                    const value_str = brace_content[0..close_brace];
                    var value_split = std.mem.splitScalar(u8, value_str, ',');
                    while (value_split.next()) |value_decl| {
                        const v = std.mem.trim(u8, value_decl, " \t\r\n");
                        if (v.len == 0) continue;

                        try values.append(self.allocator, EnumValue{
                            .name = try self.allocator.dupe(u8, v),
                        });
                    }
                }
            }
        }

        try self.declarations.append(self.allocator, Declaration{
            .type = .enum_type,
            .is_public = is_public,
            .comment = if (comment) |c| Comment{ .content = c } else null,
            .enum_values = if (values.items.len > 0) try self.allocator.dupe(EnumValue, values.items) else null,
        });
    }

    fn parseUnionDeclaration(self: *Self, line: []const u8, comment: ?[]const u8, is_public: bool) !void {
        const const_idx = std.mem.indexOf(u8, line, "const ") orelse return;
        const union_part = line[const_idx + 6 ..];
        const eq_idx = std.mem.indexOf(u8, union_part, "=") orelse return;
        _ = std.mem.trim(u8, union_part[0..eq_idx], " \t");

        var fields = std.ArrayListUnmanaged(StructField){};
        defer fields.deinit(self.allocator);

        // Try to extract fields from same line
        if (std.mem.indexOf(u8, line, "union")) |union_idx| {
            const after_union = line[union_idx + 5 ..];
            if (std.mem.indexOf(u8, after_union, "{")) |open_brace| {
                const brace_content = after_union[open_brace + 1 ..];
                if (std.mem.indexOf(u8, brace_content, "}")) |close_brace| {
                    const field_str = brace_content[0..close_brace];
                    var field_split = std.mem.splitScalar(u8, field_str, ',');
                    while (field_split.next()) |field_decl| {
                        const f = std.mem.trim(u8, field_decl, " \t\r\n");
                        if (f.len == 0) continue;

                        if (std.mem.indexOf(u8, f, ":")) |colon_idx| {
                            const fname = std.mem.trim(u8, f[0..colon_idx], " \t");
                            const ftype_part = f[colon_idx + 1 ..];
                            const ftype = std.mem.trim(u8, ftype_part, " \t");

                            try fields.append(self.allocator, StructField{
                                .name = try self.allocator.dupe(u8, fname),
                                .field_type = try self.allocator.dupe(u8, ftype),
                            });
                        }
                    }
                }
            }
        }

        try self.declarations.append(self.allocator, Declaration{
            .type = .union_type,
            .is_public = is_public,
            .comment = if (comment) |c| Comment{ .content = c } else null,
            .struct_fields = if (fields.items.len > 0) try self.allocator.dupe(StructField, fields.items) else null,
        });
    }

    fn parseConstantDeclaration(self: *Self, line: []const u8, comment: ?[]const u8, is_public: bool) !void {
        const const_idx = std.mem.indexOf(u8, line, "const ") orelse
            std.mem.indexOf(u8, line, "var ") orelse return;
        const const_part = line[const_idx + 6 ..];
        const eq_idx = std.mem.indexOf(u8, const_part, "=") orelse return;
        _ = std.mem.trim(u8, const_part[0..eq_idx], " \t");

        try self.declarations.append(self.allocator, Declaration{
            .type = .constant,
            .is_public = is_public,
            .comment = if (comment) |c| Comment{ .content = c } else null,
        });
    }

    /// Get parsed declarations
    pub fn getDeclarations(self: Self) []const Declaration {
        return self.declarations.items;
    }

    /// Get module-level comment
    pub fn getModuleComment(self: Self) ?Comment {
        return self.module_comment;
    }

    /// Generate markdown documentation
    pub fn generateMarkdown(self: Self, writer: anytype) !void {
        // Module overview
        if (self.module_comment) |mc| {
            try writer.print("# Overview\n\n{s}\n\n", .{mc.content});
        }

        // Generate documentation for each declaration
        for (self.declarations.items) |decl| {
            if (!decl.is_public) continue;

            switch (decl.type) {
                .function => {
                    if (decl.signature) |sig| {
                        try writer.print("## `fn {s}(", .{sig.name});

                        for (sig.parameters, 0..) |param, i| {
                            if (i > 0) try writer.print(", ", .{});
                            try writer.print("{s}: {s}", .{ param.name, param.param_type });
                        }

                        try writer.print(") {s}`\n\n", .{sig.return_type});

                        if (decl.comment) |c| {
                            try writer.print("{s}\n\n", .{c.content});
                        }
                    }
                },
                .struct_type => {
                    try writer.print("## Struct\n\n", .{});
                    if (decl.comment) |c| {
                        try writer.print("{s}\n\n", .{c.content});
                    }
                    if (decl.struct_fields) |fields| {
                        try writer.print("### Fields\n\n", .{});
                        for (fields) |field| {
                            try writer.print("- `{s}: {s}`", .{ field.name, field.field_type });
                            if (field.comment) |c| {
                                try writer.print(" - {s}", .{c.content});
                            }
                            try writer.print("\n", .{});
                        }
                        try writer.print("\n", .{});
                    }
                },
                .enum_type => {
                    try writer.print("## Enum\n\n", .{});
                    if (decl.comment) |c| {
                        try writer.print("{s}\n\n", .{c.content});
                    }
                    if (decl.enum_values) |values| {
                        try writer.print("### Values\n\n", .{});
                        for (values) |val| {
                            try writer.print("- `{s}`", .{val.name});
                            if (val.comment) |c| {
                                try writer.print(" - {s}", .{c.content});
                            }
                            try writer.print("\n", .{});
                        }
                        try writer.print("\n", .{});
                    }
                },
                .union_type => {
                    try writer.print("## Union\n\n", .{});
                    if (decl.comment) |c| {
                        try writer.print("{s}\n\n", .{c.content});
                    }
                    if (decl.struct_fields) |fields| {
                        try writer.print("### Fields\n\n", .{});
                        for (fields) |field| {
                            try writer.print("- `{s}: {s}`", .{ field.name, field.field_type });
                            if (field.comment) |c| {
                                try writer.print(" - {s}", .{c.content});
                            }
                            try writer.print("\n", .{});
                        }
                        try writer.print("\n", .{});
                    }
                },
                .constant => {
                    try writer.print("## Constant\n\n", .{});
                    if (decl.comment) |c| {
                        try writer.print("{s}\n\n", .{c.content});
                    }
                },
            }
        }
    }

    /// Parse a directory recursively (stub for API testing)
    pub fn parseDirectory(self: *Self, path: []const u8) !void {
        _ = self;
        _ = path;
        // TODO: Implement directory scanning
    }
};
