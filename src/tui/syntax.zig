const std = @import("std");
const style = @import("style.zig");
const Style = style.Style;
const Color = style.Color;

/// Token type for syntax highlighting
pub const TokenType = enum {
    // Literals
    keyword,
    identifier,
    string,
    number,
    boolean,
    null_literal,

    // Operators & punctuation
    operator,
    punctuation,
    delimiter,

    // Structure
    comment,
    whitespace,
    newline,

    // Special
    error_token,
    unknown,

    pub fn defaultStyle(self: TokenType) Style {
        return switch (self) {
            .keyword => Style{ .fg = Color.magenta, .bold = true },
            .identifier => Style{ .fg = Color.white },
            .string => Style{ .fg = Color.green },
            .number => Style{ .fg = Color.cyan },
            .boolean => Style{ .fg = Color.yellow, .bold = true },
            .null_literal => Style{ .fg = Color.yellow, .italic = true },
            .operator => Style{ .fg = Color.red },
            .punctuation => Style{ .fg = Color.white },
            .delimiter => Style{ .fg = Color.white },
            .comment => Style{ .fg = Color{ .indexed = 8 }, .italic = true }, // gray
            .whitespace, .newline => Style{},
            .error_token => Style{ .fg = Color.red, .bold = true, .underline = true },
            .unknown => Style{},
        };
    }
};

/// A token in the source code
pub const Token = struct {
    type: TokenType,
    start: usize,
    end: usize,

    pub fn length(self: Token) usize {
        return self.end - self.start;
    }

    pub fn text(self: Token, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

/// Language identifier
pub const Language = enum {
    none,
    zig,
    c,
    python,
    javascript,
    json,
    markdown,

    pub fn fromExtension(ext: []const u8) Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) return .c;
        if (std.mem.eql(u8, ext, ".py")) return .python;
        if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".mjs")) return .javascript;
        if (std.mem.eql(u8, ext, ".json")) return .json;
        if (std.mem.eql(u8, ext, ".md")) return .markdown;
        return .none;
    }
};

/// Lexer interface - tokenizes source code
pub const Lexer = struct {
    language: Language,
    source: []const u8,
    pos: usize,

    pub fn init(language: Language, source: []const u8) Lexer {
        return .{
            .language = language,
            .source = source,
            .pos = 0,
        };
    }

    /// Tokenize entire source into a list
    pub fn tokenize(self: *Lexer, allocator: std.mem.Allocator) ![]Token {
        var tokens = std.ArrayList(Token){};
        defer tokens.deinit(allocator);

        self.pos = 0;
        while (self.pos < self.source.len) {
            const token = try self.nextToken();
            try tokens.append(allocator, token);
        }

        return tokens.toOwnedSlice(allocator);
    }

    /// Get the next token
    pub fn nextToken(self: *Lexer) !Token {
        if (self.pos >= self.source.len) {
            return Token{ .type = .unknown, .start = self.pos, .end = self.pos };
        }

        return switch (self.language) {
            .none => self.nextPlainToken(),
            .zig => self.nextZigToken(),
            .c => self.nextCToken(),
            .python => self.nextPythonToken(),
            .javascript => self.nextJavaScriptToken(),
            .json => self.nextJsonToken(),
            .markdown => self.nextMarkdownToken(),
        };
    }

    fn nextPlainToken(self: *Lexer) !Token {
        const start = self.pos;
        if (self.source[self.pos] == '\n') {
            self.pos += 1;
            return Token{ .type = .newline, .start = start, .end = self.pos };
        }

        while (self.pos < self.source.len and self.source[self.pos] != '\n') {
            self.pos += 1;
        }

        return Token{ .type = .identifier, .start = start, .end = self.pos };
    }

    fn nextZigToken(self: *Lexer) !Token {
        const start = self.pos;
        const c = self.source[self.pos];

        // Whitespace
        if (c == ' ' or c == '\t' or c == '\r') {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const next = self.source[self.pos];
                if (next != ' ' and next != '\t' and next != '\r') break;
                self.pos += 1;
            }
            return Token{ .type = .whitespace, .start = start, .end = self.pos };
        }

        // Newline
        if (c == '\n') {
            self.pos += 1;
            return Token{ .type = .newline, .start = start, .end = self.pos };
        }

        // Line comment
        if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
            self.pos += 2;
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.pos += 1;
            }
            return Token{ .type = .comment, .start = start, .end = self.pos };
        }

        // String literal
        if (c == '"') {
            self.pos += 1;
            var escaped = false;
            while (self.pos < self.source.len) {
                const ch = self.source[self.pos];
                self.pos += 1;
                if (escaped) {
                    escaped = false;
                    continue;
                }
                if (ch == '\\') {
                    escaped = true;
                    continue;
                }
                if (ch == '"') break;
            }
            return Token{ .type = .string, .start = start, .end = self.pos };
        }

        // Number
        if (std.ascii.isDigit(c)) {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const ch = self.source[self.pos];
                if (!std.ascii.isDigit(ch) and ch != '.' and ch != '_' and
                    !std.ascii.isAlphabetic(ch)) break; // allow 0x, 0b prefixes
                self.pos += 1;
            }
            return Token{ .type = .number, .start = start, .end = self.pos };
        }

        // Identifier or keyword
        if (std.ascii.isAlphabetic(c) or c == '_' or c == '@') {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const ch = self.source[self.pos];
                if (!std.ascii.isAlphanumeric(ch) and ch != '_') break;
                self.pos += 1;
            }

            const text = self.source[start..self.pos];
            const token_type = if (self.isZigKeyword(text)) TokenType.keyword
                else if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) TokenType.boolean
                else if (std.mem.eql(u8, text, "null")) TokenType.null_literal
                else TokenType.identifier;

            return Token{ .type = token_type, .start = start, .end = self.pos };
        }

        // Operators and punctuation
        const operators = "+-*/%=<>!&|^~";
        const punctuation = "(){}[];:,.";

        if (std.mem.indexOfScalar(u8, operators, c) != null) {
            self.pos += 1;
            return Token{ .type = .operator, .start = start, .end = self.pos };
        }

        if (std.mem.indexOfScalar(u8, punctuation, c) != null) {
            self.pos += 1;
            return Token{ .type = .punctuation, .start = start, .end = self.pos };
        }

        // Unknown
        self.pos += 1;
        return Token{ .type = .unknown, .start = start, .end = self.pos };
    }

    fn isZigKeyword(self: *Lexer, text: []const u8) bool {
        _ = self;
        const keywords = [_][]const u8{
            "const", "var", "fn", "pub", "return", "if", "else", "switch",
            "while", "for", "break", "continue", "struct", "enum", "union",
            "error", "try", "catch", "defer", "errdefer", "async", "await",
            "suspend", "resume", "comptime", "inline", "export", "extern",
            "packed", "align", "linksection", "callconv", "noalias",
            "anytype", "anyframe", "usingnamespace", "test", "and", "or",
            "orelse", "unreachable", "undefined",
        };

        for (keywords) |kw| {
            if (std.mem.eql(u8, text, kw)) return true;
        }
        return false;
    }

    fn nextCToken(self: *Lexer) !Token {
        // Similar to Zig but with C keywords
        // Reuse Zig lexer for basic structure
        const token = try self.nextZigToken();

        // Override keyword detection
        if (token.type == .identifier or token.type == .keyword) {
            const text = self.source[token.start..token.end];
            if (self.isCKeyword(text)) {
                return Token{ .type = .keyword, .start = token.start, .end = token.end };
            }
        }

        return token;
    }

    fn isCKeyword(self: *Lexer, text: []const u8) bool {
        _ = self;
        const keywords = [_][]const u8{
            "auto", "break", "case", "char", "const", "continue", "default",
            "do", "double", "else", "enum", "extern", "float", "for", "goto",
            "if", "int", "long", "register", "return", "short", "signed",
            "sizeof", "static", "struct", "switch", "typedef", "union",
            "unsigned", "void", "volatile", "while",
        };

        for (keywords) |kw| {
            if (std.mem.eql(u8, text, kw)) return true;
        }
        return false;
    }

    fn nextPythonToken(self: *Lexer) !Token {
        const start = self.pos;
        const c = self.source[self.pos];

        // Whitespace
        if (c == ' ' or c == '\t' or c == '\r') {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const next = self.source[self.pos];
                if (next != ' ' and next != '\t' and next != '\r') break;
                self.pos += 1;
            }
            return Token{ .type = .whitespace, .start = start, .end = self.pos };
        }

        // Newline
        if (c == '\n') {
            self.pos += 1;
            return Token{ .type = .newline, .start = start, .end = self.pos };
        }

        // Comment
        if (c == '#') {
            self.pos += 1;
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.pos += 1;
            }
            return Token{ .type = .comment, .start = start, .end = self.pos };
        }

        // String literal
        if (c == '"' or c == '\'') {
            const quote = c;
            self.pos += 1;
            while (self.pos < self.source.len and self.source[self.pos] != quote) {
                if (self.source[self.pos] == '\\') self.pos += 1; // skip escaped char
                self.pos += 1;
            }
            if (self.pos < self.source.len) self.pos += 1; // closing quote
            return Token{ .type = .string, .start = start, .end = self.pos };
        }

        // Number
        if (std.ascii.isDigit(c)) {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const ch = self.source[self.pos];
                if (!std.ascii.isDigit(ch) and ch != '.') break;
                self.pos += 1;
            }
            return Token{ .type = .number, .start = start, .end = self.pos };
        }

        // Identifier or keyword
        if (std.ascii.isAlphabetic(c) or c == '_') {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const ch = self.source[self.pos];
                if (!std.ascii.isAlphanumeric(ch) and ch != '_') break;
                self.pos += 1;
            }

            const text = self.source[start..self.pos];
            const token_type = if (self.isPythonKeyword(text)) TokenType.keyword
                else if (std.mem.eql(u8, text, "True") or std.mem.eql(u8, text, "False")) TokenType.boolean
                else if (std.mem.eql(u8, text, "None")) TokenType.null_literal
                else TokenType.identifier;

            return Token{ .type = token_type, .start = start, .end = self.pos };
        }

        // Operators
        const operators = "+-*/%=<>!&|^~";
        if (std.mem.indexOfScalar(u8, operators, c) != null) {
            self.pos += 1;
            return Token{ .type = .operator, .start = start, .end = self.pos };
        }

        // Punctuation
        const punctuation = "(){}[];:,.";
        if (std.mem.indexOfScalar(u8, punctuation, c) != null) {
            self.pos += 1;
            return Token{ .type = .punctuation, .start = start, .end = self.pos };
        }

        // Unknown
        self.pos += 1;
        return Token{ .type = .unknown, .start = start, .end = self.pos };
    }

    fn isPythonKeyword(self: *Lexer, text: []const u8) bool {
        _ = self;
        const keywords = [_][]const u8{
            "and", "as", "assert", "async", "await", "break", "class",
            "continue", "def", "del", "elif", "else", "except", "finally",
            "for", "from", "global", "if", "import", "in", "is", "lambda",
            "nonlocal", "not", "or", "pass", "raise", "return", "try",
            "while", "with", "yield",
        };

        for (keywords) |kw| {
            if (std.mem.eql(u8, text, kw)) return true;
        }
        return false;
    }

    fn nextJavaScriptToken(self: *Lexer) !Token {
        const start = self.pos;
        const c = self.source[self.pos];

        // Whitespace
        if (c == ' ' or c == '\t' or c == '\r') {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const next = self.source[self.pos];
                if (next != ' ' and next != '\t' and next != '\r') break;
                self.pos += 1;
            }
            return Token{ .type = .whitespace, .start = start, .end = self.pos };
        }

        // Newline
        if (c == '\n') {
            self.pos += 1;
            return Token{ .type = .newline, .start = start, .end = self.pos };
        }

        // Comment
        if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
            self.pos += 2;
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.pos += 1;
            }
            return Token{ .type = .comment, .start = start, .end = self.pos };
        }

        // String literal
        if (c == '"' or c == '\'' or c == '`') {
            const quote = c;
            self.pos += 1;
            while (self.pos < self.source.len and self.source[self.pos] != quote) {
                if (self.source[self.pos] == '\\') self.pos += 1;
                self.pos += 1;
            }
            if (self.pos < self.source.len) self.pos += 1;
            return Token{ .type = .string, .start = start, .end = self.pos };
        }

        // Number
        if (std.ascii.isDigit(c)) {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const ch = self.source[self.pos];
                if (!std.ascii.isDigit(ch) and ch != '.') break;
                self.pos += 1;
            }
            return Token{ .type = .number, .start = start, .end = self.pos };
        }

        // Identifier or keyword
        if (std.ascii.isAlphabetic(c) or c == '_' or c == '$') {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const ch = self.source[self.pos];
                if (!std.ascii.isAlphanumeric(ch) and ch != '_' and ch != '$') break;
                self.pos += 1;
            }

            const text = self.source[start..self.pos];
            const token_type = if (self.isJavaScriptKeyword(text)) TokenType.keyword
                else if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) TokenType.boolean
                else if (std.mem.eql(u8, text, "null") or std.mem.eql(u8, text, "undefined")) TokenType.null_literal
                else TokenType.identifier;

            return Token{ .type = token_type, .start = start, .end = self.pos };
        }

        // Operators
        const operators = "+-*/%=<>!&|^~";
        if (std.mem.indexOfScalar(u8, operators, c) != null) {
            self.pos += 1;
            return Token{ .type = .operator, .start = start, .end = self.pos };
        }

        // Punctuation
        const punctuation = "(){}[];:,.";
        if (std.mem.indexOfScalar(u8, punctuation, c) != null) {
            self.pos += 1;
            return Token{ .type = .punctuation, .start = start, .end = self.pos };
        }

        // Unknown
        self.pos += 1;
        return Token{ .type = .unknown, .start = start, .end = self.pos };
    }

    fn isJavaScriptKeyword(self: *Lexer, text: []const u8) bool {
        _ = self;
        const keywords = [_][]const u8{
            "break", "case", "catch", "class", "const", "continue", "debugger",
            "default", "delete", "do", "else", "export", "extends", "finally",
            "for", "function", "if", "import", "in", "instanceof", "let", "new",
            "return", "super", "switch", "this", "throw", "try", "typeof", "var",
            "void", "while", "with", "yield", "async", "await",
        };

        for (keywords) |kw| {
            if (std.mem.eql(u8, text, kw)) return true;
        }
        return false;
    }

    fn nextJsonToken(self: *Lexer) !Token {
        const start = self.pos;
        const c = self.source[self.pos];

        // Whitespace
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const next = self.source[self.pos];
                if (next != ' ' and next != '\t' and next != '\r' and next != '\n') break;
                self.pos += 1;
            }
            if (c == '\n') {
                return Token{ .type = .newline, .start = start, .end = self.pos };
            }
            return Token{ .type = .whitespace, .start = start, .end = self.pos };
        }

        // String
        if (c == '"') {
            self.pos += 1;
            while (self.pos < self.source.len and self.source[self.pos] != '"') {
                if (self.source[self.pos] == '\\') self.pos += 1;
                self.pos += 1;
            }
            if (self.pos < self.source.len) self.pos += 1;
            return Token{ .type = .string, .start = start, .end = self.pos };
        }

        // Number
        if (std.ascii.isDigit(c) or c == '-') {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const ch = self.source[self.pos];
                if (!std.ascii.isDigit(ch) and ch != '.' and ch != 'e' and ch != 'E' and ch != '+' and ch != '-') break;
                self.pos += 1;
            }
            return Token{ .type = .number, .start = start, .end = self.pos };
        }

        // Keywords (true, false, null)
        if (std.ascii.isAlphabetic(c)) {
            self.pos += 1;
            while (self.pos < self.source.len and std.ascii.isAlphabetic(self.source[self.pos])) {
                self.pos += 1;
            }

            const text = self.source[start..self.pos];
            if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) {
                return Token{ .type = .boolean, .start = start, .end = self.pos };
            }
            if (std.mem.eql(u8, text, "null")) {
                return Token{ .type = .null_literal, .start = start, .end = self.pos };
            }
            return Token{ .type = .error_token, .start = start, .end = self.pos };
        }

        // Punctuation
        const punctuation = "{}[]:,";
        if (std.mem.indexOfScalar(u8, punctuation, c) != null) {
            self.pos += 1;
            return Token{ .type = .punctuation, .start = start, .end = self.pos };
        }

        // Unknown
        self.pos += 1;
        return Token{ .type = .error_token, .start = start, .end = self.pos };
    }

    fn nextMarkdownToken(self: *Lexer) !Token {
        const start = self.pos;
        const c = self.source[self.pos];

        // Newline
        if (c == '\n') {
            self.pos += 1;
            return Token{ .type = .newline, .start = start, .end = self.pos };
        }

        // Heading
        if (c == '#' and (start == 0 or self.source[start - 1] == '\n')) {
            self.pos += 1;
            while (self.pos < self.source.len and self.source[self.pos] == '#') {
                self.pos += 1;
            }
            return Token{ .type = .keyword, .start = start, .end = self.pos };
        }

        // Bold/italic markers
        if (c == '*' or c == '_') {
            self.pos += 1;
            if (self.pos < self.source.len and self.source[self.pos] == c) {
                self.pos += 1; // ** or __
            }
            return Token{ .type = .operator, .start = start, .end = self.pos };
        }

        // Code block marker
        if (c == '`') {
            self.pos += 1;
            if (self.pos < self.source.len and self.source[self.pos] == '`') {
                self.pos += 1;
                if (self.pos < self.source.len and self.source[self.pos] == '`') {
                    self.pos += 1; // ```
                }
            }
            return Token{ .type = .delimiter, .start = start, .end = self.pos };
        }

        // List marker
        if ((c == '-' or c == '*' or c == '+') and
            (start == 0 or self.source[start - 1] == '\n') and
            self.pos + 1 < self.source.len and self.source[self.pos + 1] == ' ') {
            self.pos += 1;
            return Token{ .type = .operator, .start = start, .end = self.pos };
        }

        // Whitespace
        if (c == ' ' or c == '\t') {
            self.pos += 1;
            while (self.pos < self.source.len) {
                const next = self.source[self.pos];
                if (next != ' ' and next != '\t') break;
                self.pos += 1;
            }
            return Token{ .type = .whitespace, .start = start, .end = self.pos };
        }

        // Regular text
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '\n' or ch == '#' or ch == '*' or ch == '_' or ch == '`') break;
            self.pos += 1;
        }

        return Token{ .type = .identifier, .start = start, .end = self.pos };
    }
};

/// Theme for syntax highlighting
pub const SyntaxTheme = struct {
    keyword: Style,
    identifier: Style,
    string: Style,
    number: Style,
    boolean: Style,
    null_literal: Style,
    operator: Style,
    punctuation: Style,
    delimiter: Style,
    comment: Style,
    whitespace: Style,
    newline: Style,
    error_token: Style,
    unknown: Style,

    pub fn default() SyntaxTheme {
        return .{
            .keyword = TokenType.keyword.defaultStyle(),
            .identifier = TokenType.identifier.defaultStyle(),
            .string = TokenType.string.defaultStyle(),
            .number = TokenType.number.defaultStyle(),
            .boolean = TokenType.boolean.defaultStyle(),
            .null_literal = TokenType.null_literal.defaultStyle(),
            .operator = TokenType.operator.defaultStyle(),
            .punctuation = TokenType.punctuation.defaultStyle(),
            .delimiter = TokenType.delimiter.defaultStyle(),
            .comment = TokenType.comment.defaultStyle(),
            .whitespace = TokenType.whitespace.defaultStyle(),
            .newline = TokenType.newline.defaultStyle(),
            .error_token = TokenType.error_token.defaultStyle(),
            .unknown = TokenType.unknown.defaultStyle(),
        };
    }

    pub fn getStyle(self: SyntaxTheme, token_type: TokenType) Style {
        return switch (token_type) {
            .keyword => self.keyword,
            .identifier => self.identifier,
            .string => self.string,
            .number => self.number,
            .boolean => self.boolean,
            .null_literal => self.null_literal,
            .operator => self.operator,
            .punctuation => self.punctuation,
            .delimiter => self.delimiter,
            .comment => self.comment,
            .whitespace => self.whitespace,
            .newline => self.newline,
            .error_token => self.error_token,
            .unknown => self.unknown,
        };
    }
};

// Tests
test "TokenType.defaultStyle" {
    const keyword_style = TokenType.keyword.defaultStyle();
    try std.testing.expect(keyword_style.fg != null);
    if (keyword_style.fg) |fg| {
        try std.testing.expect(std.meta.eql(fg, Color.magenta));
    }
    try std.testing.expect(keyword_style.bold);
}

test "Token basics" {
    const token = Token{ .type = .keyword, .start = 0, .end = 5 };
    try std.testing.expectEqual(@as(usize, 5), token.length());

    const source = "const x = 5;";
    const text = token.text(source);
    try std.testing.expectEqualStrings("const", text);
}

test "Language.fromExtension" {
    try std.testing.expectEqual(Language.zig, Language.fromExtension(".zig"));
    try std.testing.expectEqual(Language.c, Language.fromExtension(".c"));
    try std.testing.expectEqual(Language.python, Language.fromExtension(".py"));
    try std.testing.expectEqual(Language.javascript, Language.fromExtension(".js"));
    try std.testing.expectEqual(Language.json, Language.fromExtension(".json"));
    try std.testing.expectEqual(Language.markdown, Language.fromExtension(".md"));
    try std.testing.expectEqual(Language.none, Language.fromExtension(".txt"));
}

test "Lexer.Zig - keywords" {
    const source = "const fn pub";
    var lexer = Lexer.init(.zig, source);

    const t1 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.keyword, t1.type);
    try std.testing.expectEqualStrings("const", t1.text(source));

    _ = try lexer.nextToken(); // whitespace

    const t2 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.keyword, t2.type);
    try std.testing.expectEqualStrings("fn", t2.text(source));
}

test "Lexer.Zig - string" {
    const source = "\"hello world\"";
    var lexer = Lexer.init(.zig, source);

    const token = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.string, token.type);
    try std.testing.expectEqualStrings("\"hello world\"", token.text(source));
}

test "Lexer.Zig - number" {
    const source = "123 0xFF 3.14";
    var lexer = Lexer.init(.zig, source);

    const t1 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.number, t1.type);
    try std.testing.expectEqualStrings("123", t1.text(source));

    _ = try lexer.nextToken(); // whitespace

    const t2 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.number, t2.type);
    try std.testing.expectEqualStrings("0xFF", t2.text(source));
}

test "Lexer.Zig - comment" {
    const source = "// this is a comment\nconst x = 5;";
    var lexer = Lexer.init(.zig, source);

    const t1 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.comment, t1.type);
    try std.testing.expectEqualStrings("// this is a comment", t1.text(source));
}

test "Lexer.Zig - boolean" {
    const source = "true false";
    var lexer = Lexer.init(.zig, source);

    const t1 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.boolean, t1.type);

    _ = try lexer.nextToken(); // whitespace

    const t2 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.boolean, t2.type);
}

test "Lexer.Zig - operators" {
    const source = "+ - * / =";
    var lexer = Lexer.init(.zig, source);

    const t1 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.operator, t1.type);
    try std.testing.expectEqualStrings("+", t1.text(source));
}

test "Lexer.Python - keywords" {
    const source = "def if else";
    var lexer = Lexer.init(.python, source);

    const t1 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.keyword, t1.type);
    try std.testing.expectEqualStrings("def", t1.text(source));
}

test "Lexer.Python - comment" {
    const source = "# comment\nx = 5";
    var lexer = Lexer.init(.python, source);

    const t1 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.comment, t1.type);
    try std.testing.expectEqualStrings("# comment", t1.text(source));
}

test "Lexer.JavaScript - keywords" {
    const source = "const let var function";
    var lexer = Lexer.init(.javascript, source);

    const t1 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.keyword, t1.type);
    try std.testing.expectEqualStrings("const", t1.text(source));
}

test "Lexer.JSON - structure" {
    const source = "{\"key\": 123, \"flag\": true}";
    var lexer = Lexer.init(.json, source);

    const t1 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.punctuation, t1.type);
    try std.testing.expectEqualStrings("{", t1.text(source));

    const t2 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.string, t2.type);
    try std.testing.expectEqualStrings("\"key\"", t2.text(source));
}

test "Lexer.Markdown - heading" {
    const source = "# Heading\ntext";
    var lexer = Lexer.init(.markdown, source);

    const t1 = try lexer.nextToken();
    try std.testing.expectEqual(TokenType.keyword, t1.type);
    try std.testing.expectEqualStrings("#", t1.text(source));
}

test "Lexer.tokenize - full source" {
    const allocator = std.testing.allocator;
    const source = "const x = 5;";
    var lexer = Lexer.init(.zig, source);

    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len > 0);
    try std.testing.expectEqual(TokenType.keyword, tokens[0].type);
}

test "SyntaxTheme.default" {
    const theme = SyntaxTheme.default();
    const keyword_style = theme.getStyle(.keyword);
    try std.testing.expect(keyword_style.fg != null);
    if (keyword_style.fg) |fg| {
        try std.testing.expect(std.meta.eql(fg, Color.magenta));
    }
}

test "SyntaxTheme.getStyle" {
    const theme = SyntaxTheme.default();

    try std.testing.expect(theme.getStyle(.keyword).bold);
    try std.testing.expect(theme.getStyle(.comment).italic);

    const string_style = theme.getStyle(.string);
    try std.testing.expect(string_style.fg != null);
    if (string_style.fg) |fg| {
        try std.testing.expect(std.meta.eql(fg, Color.green));
    }
}
