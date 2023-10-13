const std = @import("std");
const BufferedReader = std.io.BufferedReader;
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const tk = @import("../tokenizer/tokenizer.zig");
const Location = tk.Location;
const Token = tk.Token;
const Tokenizer = tk.Tokenizer;
const TokenType = tk.TokenType;
const TokenizerError = tk.TokenizerError;
const TokenizerErrors = tk.TokenizerErrors;
const u8util = @import("../util/u8util.zig");

const Errors = error{ InternalException, UnexpectedToken };

pub const LexerErrors = Errors || TokenizerErrors;

pub const LexerError = struct { err: Errors, message: []const u8, location: ?Location };

pub const TokenReader = *const fn (*?TokenizerError) TokenizerErrors!Token;

pub const Registers = enum { eax };
pub const AccessType = enum { direct, indirect };
pub const ValueType = enum { identifier, constant };
pub const RightValue = struct { accessType: AccessType, value: Value };
pub const Value = union(ValueType) { identifier: []const u8, constant: usize };

pub fn lexer(tokenizer: *Tokenizer, allocator: Allocator) Lexer {
    return .{ .tokenizer = tokenizer, .allocator = allocator };
}

pub const Lexer = struct {
    const Self = @This();

    tokenizer: *Tokenizer,
    allocator: Allocator,
    err: ?LexerError = undefined,
    nextToken: ?Token = null,
    labels: std.StringHashMap(Token) = undefined,
    currentIndent: u8 = 0,

    pub fn deinit(self: *Self) void {
        for (self.labels.valueIterator()) |value| value.deinit();
        self.labels.deinit();
    }

    pub fn parse(self: *Self) LexerErrors!void {
        self.labels = std.StringHashMap(Token).init(self.allocator);
        while (true) {
            const peek = try self.peekToken();
            if (peek.type == .EOF) break;
            try self.parseInstruction();
        }
    }

    fn parseInstruction(self: *Self) LexerErrors!void {
        // [label:] [expression]\n
        try self.skipAll(.NewLine);
        var peek = try self.peekToken();
        if (peek.type == .Identifier) {
            var token = try self.expect(.Identifier, null);
            var identifierToken = token.clone(self.allocator) catch {
                return self.createError(Errors.InternalException, "An internal exception occurred.", null);
            };
            peek = try self.peekToken();

            var indent: u8 = 0;
            _ = indent;
            if (peek.type == .Symbol and std.mem.eql(u8, peek.lexeme, ":")) {
                self.currentIndent = @intCast(peek.location.column);
                self.currentIndent += 2;
                // Label
                self.labels.put(token.lexeme, identifierToken) catch {
                    return self.createError(Errors.InternalException, "An internal exception occurred.", null);
                };
                _ = try self.expect(.Symbol, ":");
                std.log.info("Found {s} label.", .{identifierToken.lexeme});

                peek = try self.peekToken();
                if (peek.type == .EOF) {
                    return;
                } else if (peek.type == .NewLine) {
                    try self.skipAll(.NewLine);
                    return;
                } else if (peek.type == .Identifier) {
                    try self.parseExpression(try self.expect(.Identifier, null));
                }
            } else {
                // No label
                defer identifierToken.deinit();
                try self.parseExpression(identifierToken);
                try self.skipAll(.NewLine);
            }
        }
    }

    fn parseExpression(self: *Self, identifier: Token) LexerErrors!void {
        var identifierToken = identifier.clone(self.allocator) catch {
            return self.createError(Errors.InternalException, "An internal exception occurred.", null);
        };
        defer identifierToken.deinit();
        // register (=|+=|-=) (number|*number|register)

        var operator = try self.expect(.Symbol, "=");
        switch (operator.lexeme[0]) {
            '=' => try self.parseAssignment(identifierToken),
            '+', '-' => {
                const primaryOperator = (try self.expect(.Symbol, null)).clone(self.allocator) catch {
                    return self.createError(Errors.InternalException, "An internal exception occurred.", null);
                };
                const secondaryOperator = try self.peekToken();
                switch (secondaryOperator.lexeme[0]) {
                    '=' => try self.parseIncrementAndAssign(identifierToken),
                    else => try self.parseBinaryExpression(identifierToken, primaryOperator),
                }
            },
            else => return self.createError(Errors.UnexpectedToken, "Invalid operator.", operator.location),
        }
    }

    fn parseIncrementAndAssign(self: *Self, identifier: Token) LexerErrors!void {
        _ = identifier;
        _ = self;
        unreachable;
    }

    fn parseBinaryExpression(self: *Self, identifier: Token, operator: Token) LexerErrors!void {
        _ = operator;
        _ = identifier;
        _ = self;
        unreachable;
    }

    fn parseAssignment(self: *Self, identifier: Token) LexerErrors!void {
        // identifier = (number|*number|register)
        const value = try self.parseValue();
        switch (value.value) {
            ValueType.constant => std.log.info("{s} = [{}:{d}]", .{ identifier.lexeme, value.accessType, value.value.constant }),
            ValueType.identifier => std.log.info("{s} = [{}:{s}]", .{ identifier.lexeme, value.accessType, value.value.identifier }),
        }
    }

    fn parseValue(self: *Self) LexerErrors!RightValue {
        // (number|*number|register)
        var token = try self.readToken();
        switch (token.type) {
            .Number => {
                return .{ .accessType = .direct, .value = .{ .constant = 1337 } };
            },
            .Symbol => {
                const value = try self.readToken();
                switch (value.type) {
                    .Identifier => return .{ .accessType = .indirect, .value = .{ .identifier = value.lexeme } },
                    .Number => return .{ .accessType = .indirect, .value = .{ .constant = 2337 } },
                    else => return self.createError(Errors.UnexpectedToken, "Invalid r-value in assigment.", value.location),
                }
            },
            .Identifier => {
                const identifier = token.clone(self.allocator) catch {
                    return self.createError(Errors.InternalException, "An internal exception occurred.", null);
                };
                return .{ .accessType = .direct, .value = .{ .identifier = identifier.lexeme } };
            },
            else => return self.createError(Errors.UnexpectedToken, "Invalid r-value in assigment.", token.location),
        }
    }

    fn skipOne(self: *Self, tokenType: TokenType) LexerErrors!void {
        _ = try self.expect(tokenType, null);
    }

    fn skipAll(self: *Self, tokenType: TokenType) LexerErrors!void {
        while ((try self.peekToken()).type == tokenType) try self.skipOne(tokenType);
    }

    fn skipMany(self: *Self, tokenType: TokenType, count: u8) LexerErrors!void {
        for (0..count) |_| try self.skipOne(tokenType);
    }

    fn skipAtMost(self: *Self, tokenType: TokenType, count: u8) LexerErrors!void {
        var skipped: u8 = 0;
        while (skipped < count and (try self.peekToken()).type == tokenType) {
            try self.skipOne(tokenType);
            skipped += 1;
        }
    }

    fn expect(self: *Self, expected: TokenType, lexeme: ?[]const u8) LexerErrors!Token {
        const token = try self.readToken();
        if (token.type != expected or (lexeme != null and !std.mem.eql(u8, token.lexeme, lexeme.?))) {
            const message = std.fmt.allocPrint(self.allocator, "Expected {} ({any}) but found {} ({s}).", .{ expected, lexeme, token.type, token.lexeme }) catch {
                return self.createError(Errors.InternalException, "An internal exception occurred.", null);
            };
            return self.createError(Errors.UnexpectedToken, message, token.location);
        }
        return token;
    }

    fn peekToken(self: *Self) LexerErrors!Token {
        if (self.nextToken) |token| {
            return token;
        }

        self.nextToken = try self._readToken();
        return self.nextToken.?;
    }

    fn readToken(self: *Self) LexerErrors!Token {
        if (self.nextToken) |token| {
            defer self.nextToken = null;
            return token;
        }

        return self._readToken();
    }

    fn _readToken(self: *Self) LexerErrors!Token {
        var tokenizerError: ?TokenizerError = undefined;
        return self.tokenizer.next(&tokenizerError) catch |err| {
            std.log.info("[{}]:{d}:{d} {s}\n\r", .{ tokenizerError.?.err, tokenizerError.?.location.line, tokenizerError.?.location.column, tokenizerError.?.message });
            return err;
        };
    }

    fn createError(self: *Self, errorType: Errors, message: []const u8, location: ?Location) LexerErrors {
        self.err = .{ .err = errorType, .message = message, .location = location };
        return errorType;
    }
};
