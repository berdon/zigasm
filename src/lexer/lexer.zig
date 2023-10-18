const std = @import("std");
const BufferedReader = std.io.BufferedReader;
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const tk = @import("../tokenizer/tokenizer.zig");
const Location = tk.Location;
const Token = tk.Token;
const TokenType = tk.TokenType;
const TokenizerError = tk.TokenizerError;
const TokenizerErrors = tk.TokenizerErrors;
const u8util = @import("../util/u8util.zig");
const CPU = @import("../cpu/cpu.zig");

const Errors = error{ InternalException, UnexpectedToken, UnsupportedRegister, InvalidNumber, InvalidDirective, GeneratorError };

pub const LexerErrors = Errors || TokenizerErrors;

pub const LexerError = struct { err: Errors, message: []const u8, location: ?Location };

pub const TokenReader = *const fn (*?TokenizerError) TokenizerErrors!Token;

pub const Registers = enum { eax };
pub const AccessType = enum { direct, indirect };
pub const ValueType = enum { identifier, constant };
pub const Operand = struct {
    const Self = @This();

    accessType: AccessType,
    value: Value,
    offset: ?Value = null,
    token: ?Token,

    pub fn deinit(self: *Self) void {
        if (self.token) |*token| token.deinit();
    }

    pub fn valueFromConstant(self: Self, comptime Type: type) anyerror!Type {
        switch (self.value) {
            .identifier => unreachable,
            .constant => {},
        }
        return std.fmt.parseUnsigned(Type, self.value.constant, 0);
    }
};
pub const Value = union(ValueType) { identifier: []const u8, constant: []const u8 };

pub fn LexerType(comptime CpuType: type) type {
    return struct { cpu: CpuType };
}

pub fn lexer(comptime TokenizerType: type, comptime CpuType: type, comptime GeneratorType: type) type {
    return struct {
        const Self = @This();

        cpu: *CpuType,
        generator: GeneratorType,
        tokenizer: *TokenizerType,
        allocator: Allocator,
        err: ?LexerError = undefined,
        tokenizerError: ?TokenizerError = undefined,
        nextToken: ?Token = null,
        currentIndent: u8 = 0,

        pub fn init(cpu: *CpuType, tokenizer: *TokenizerType, allocator: Allocator, filePath: []const u8) anyerror!Self {
            var result = Self{
                .cpu = cpu,
                .generator = GeneratorType.init(allocator, cpu, filePath),
                .tokenizer = tokenizer,
                .allocator = allocator,
            };
            // result.cpu = try CpuType.init(allocator);
            return result;
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub fn parse(self: *Self) LexerErrors!void {
            while (true) {
                const peek = try self.peekToken();
                if (peek.type == .EOF) break;
                try self.parseInstruction();
                try self.skipAll(.NewLine, null);
            }
        }

        fn parseInstruction(self: *Self) LexerErrors!void {
            // [label:] [expression]\n
            try self.skipAll(.NewLine, null);
            var peek = try self.peekToken();
            if (peek.type == .SymbolAt) {
                try self.parseDirective();
            } else if (peek.type == .InstructionJmp) {
                try self.parseJmpInstruction();
            } else if (peek.type == .Identifier) {
                var token = try self.expect(.Identifier, null);
                defer token.deinit();

                peek = try self.peekToken();

                var indent: u8 = 0;
                _ = indent;
                if (peek.type == .SymbolColon) {
                    var labelToken = try token.clone(self.allocator, &self.tokenizerError);
                    defer labelToken.deinit();
                    self.currentIndent = @intCast(peek.location.column);
                    self.currentIndent += 2;
                    self.generator.processLabel(labelToken) catch |e| {
                        return self.createFormattedError(Errors.GeneratorError, "Failed to process label, \"{s}\" with Generator Error {}.", .{ labelToken.lexeme, e }, labelToken.location);
                    };
                    try self.skipOne(.SymbolColon, null);
                    std.log.info("Found {s} label.", .{labelToken.lexeme});

                    peek = try self.peekToken();
                    if (peek.type == .EOF) {
                        return;
                    } else if (peek.type == .NewLine) {
                        try self.skipAll(.NewLine, null);
                        return;
                    } else if (peek.type == .Identifier or peek.type == .SymbolAsterisk) {
                        var identifier = try self.expect(.Identifier, null);
                        defer identifier.deinit();
                        try self.parseExpression(identifier);
                    }
                } else {
                    // No label
                    try self.parseExpression(token);
                    // try self.skipAll(.NewLine, null);
                }
            } else {
                var token = try self.readToken();
                defer token.deinit();
                try self.parseExpression(token);
            }
        }

        fn parseJmpInstruction(self: *Self) LexerErrors!void {
            var instruction = try self.expect(.InstructionJmp, null);
            defer instruction.deinit();
            var operand = try self.parseValue();
            defer operand.deinit();

            self.generator.emitJump(operand, instruction.location) catch {
                return self.createFormattedError(Errors.GeneratorError, "Failed to emit jump instruction.", .{}, instruction.location);
            };
        }

        fn parseDirective(self: *Self) LexerErrors!void {
            try self.skipOne(.SymbolAt, null);
            var directive = try self.readToken();
            defer directive.deinit();

            switch (directive.type) {
                .ReservedSetBitMode => try self.parseSetBitModeDirective(),
                .ReservedSetOrigin => try self.parseSetOriginDirective(),
                else => return self.createFormattedError(Errors.InvalidDirective, "Invalid or unknown directive: \"{s}\".", .{directive.lexeme}, directive.location),
            }
        }

        /// TODO: Probably delegate CPU specific directives to the generator
        fn parseSetBitModeDirective(self: *Self) LexerErrors!void {
            try self.skipOne(.SymbolLeftParanthesis, null);
            var bitModeText = try self.expect(.Number, null);
            defer bitModeText.deinit();
            try self.skipOne(.SymbolRightParanthesis, null);

            const bitMode: CPU.BitModes = CPU.bitModeFromBits(try self.parseNumberValue(u8, bitModeText.lexeme, bitModeText.location));
            self.generator.processSetBitModeDirective(bitMode) catch |ge| return self.errorFromGeneratorError(ge, "Failed to set bit mode to {}.", .{bitMode}, bitModeText.location);
        }

        fn parseSetOriginDirective(self: *Self) LexerErrors!void {
            try self.skipOne(.SymbolLeftParanthesis, null);
            var originText = try self.expect(.Number, null);
            defer originText.deinit();
            try self.skipOne(.SymbolRightParanthesis, null);

            const origin = try self.parseNumberValue(usize, originText.lexeme, originText.location);
            self.generator.processSetOriginDirective(origin) catch |ge| return self.errorFromGeneratorError(ge, "Failed to set origin to {}.", .{origin}, originText.location);
        }

        fn parseExpression(self: *Self, token: Token) LexerErrors!void {
            // (register|*number) (=|+=|-=) (number|*number|register)
            var leftValue: Operand = undefined;
            if (token.type == .Identifier) {
                if (!self.cpu.supportsRegister(token.lexeme)) {
                    return self.createFormattedError(Errors.UnsupportedRegister, "Invalid or unsupported register ({s}).", .{token.lexeme}, token.location);
                }

                var leftValueToken = try token.clone(self.allocator, &self.tokenizerError);
                leftValue = Operand{
                    .accessType = AccessType.direct,
                    .value = Value{ .identifier = token.lexeme },
                    .token = leftValueToken,
                };
            } else if (token.type == .SymbolAsterisk) {
                try self.skipOne(.SymbolAsterisk, null);
                var memoryLocationPeek = try self.peekToken();
                if (memoryLocationPeek.type != .Number) {
                    return self.createFormattedError(Errors.UnsupportedRegister, "Invalid left-value addressing (*{s}).", .{memoryLocationPeek.lexeme}, memoryLocationPeek.location);
                }

                var leftValueToken = try self.expect(.Number, null);
                defer leftValueToken.deinit();

                leftValue = Operand{
                    .accessType = AccessType.indirect,
                    .value = Value{ .constant = memoryLocationPeek.lexeme },
                    .token = null,
                };
            } else {
                return self.createFormattedError(Errors.UnsupportedRegister, "Invalid expression.", .{}, token.location);
            }

            var operator = try self.expect(.SymbolEquals, null);
            defer operator.deinit();

            switch (operator.lexeme[0]) {
                '=' => try self.parseAssignment(leftValue, token.location),
                '+' => {
                    var primaryOperator = try self.expect(.SymbolPlus, null);
                    defer primaryOperator.deinit();

                    const secondaryOperator = try self.peekToken();
                    switch (secondaryOperator.lexeme[0]) {
                        '=' => try self.parseIncrementAndAssign(token),
                        else => try self.parseBinaryExpression(token, primaryOperator),
                    }
                },
                '-' => {
                    var primaryOperator = try self.expect(.SymbolMinus, null);
                    defer primaryOperator.deinit();

                    const secondaryOperator = try self.peekToken();
                    switch (secondaryOperator.lexeme[0]) {
                        '=' => try self.parseDecrementAndAssign(token),
                        else => try self.parseBinaryExpression(token, primaryOperator),
                    }
                },
                else => return self.createFormattedError(Errors.UnexpectedToken, "Invalid operator ({s}).", .{operator.lexeme}, operator.location),
            }
        }

        fn parseIncrementAndAssign(self: *Self, identifier: Token) LexerErrors!void {
            _ = identifier;
            _ = self;
            unreachable;
        }

        fn parseDecrementAndAssign(self: *Self, identifier: Token) LexerErrors!void {
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

        fn parseAssignment(self: *Self, leftValue: Operand, location: Location) LexerErrors!void {
            // identifier = (number|*number|register)
            var value = try self.parseValue();
            defer value.deinit();
            switch (value.value) {
                ValueType.constant => {
                    std.log.info("{} = [{}:{s}]", .{ leftValue.value, value.accessType, value.value.constant });
                    self.generator.emitAssignment(leftValue, value, location) catch {
                        return self.createError(Errors.GeneratorError, self.generator.err.?.message, self.generator.err.?.location);
                    };
                },
                ValueType.identifier => std.log.info("{} = [{}:{s}]", .{ leftValue.value, value.accessType, value.value.identifier }),
            }
        }

        fn parseValue(self: *Self) LexerErrors!Operand {
            // (number|*number|register)
            var token = try self.readToken();
            defer token.deinit();

            switch (token.type) {
                .Number => {
                    var numberToken = try token.clone(self.allocator, &self.tokenizerError);
                    return .{ .accessType = .direct, .value = .{ .constant = numberToken.lexeme }, .token = numberToken };
                },
                .SymbolAsterisk => {
                    var valueToken = try self.readToken();
                    switch (valueToken.type) {
                        .Identifier => return .{ .accessType = .indirect, .value = .{ .identifier = valueToken.lexeme }, .token = valueToken },
                        .Number => return .{ .accessType = .indirect, .value = .{ .constant = valueToken.lexeme }, .token = valueToken },
                        else => return self.createFormattedError(Errors.UnexpectedToken, "Invalid r-value in assigment (*{s}).", .{valueToken.lexeme}, valueToken.location),
                    }
                },
                .Identifier => {
                    var identifierToken = try token.clone(self.allocator, &self.tokenizerError);
                    return .{ .accessType = .direct, .value = .{ .identifier = identifierToken.lexeme }, .token = identifierToken };
                },
                else => return self.createFormattedError(Errors.UnexpectedToken, "Invalid r-value in assigment ({s}).", .{token.lexeme}, token.location),
            }
        }

        fn skipOne(self: *Self, tokenType: TokenType, lexeme: ?[]const u8) LexerErrors!void {
            var token = try self.expect(tokenType, lexeme);
            token.deinit();
        }

        fn skipAll(self: *Self, tokenType: TokenType, lexeme: ?[]const u8) LexerErrors!void {
            while ((try self.peekToken()).type == tokenType) try self.skipOne(tokenType, lexeme);
        }

        fn skipMany(self: *Self, tokenType: TokenType, lexeme: ?[]const u8, count: u8) LexerErrors!void {
            for (0..count) |_| try self.skipOne(tokenType, lexeme);
        }

        fn skipAtMost(self: *Self, tokenType: TokenType, lexeme: ?[]const u8, count: u8) LexerErrors!void {
            var skipped: u8 = 0;
            while (skipped < count and (try self.peekToken()).type == tokenType) {
                try self.skipOne(tokenType, lexeme);
                skipped += 1;
            }
        }

        fn expect(self: *Self, expected: TokenType, lexeme: ?[]const u8) LexerErrors!Token {
            const token = try self.readToken();
            if (token.type != expected or (lexeme != null and !std.mem.eql(u8, token.lexeme, lexeme.?))) {
                return self.createFormattedError(Errors.UnexpectedToken, "Expected {} ({any}) but found {} ({s}).", .{ expected, lexeme, token.type, token.lexeme }, token.location);
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

        fn parseNumberValue(self: *Self, comptime Size: type, value: []const u8, location: Location) LexerErrors!Size {
            if (value.len == 0) return self.createFormattedError(Errors.InvalidNumber, "Invalid number, \"{s}\".", .{value}, location);
            return std.fmt.parseInt(Size, value, 0) catch |e| {
                switch (e) {
                    error.Overflow => return self.createFormattedError(Errors.InvalidNumber, "Number overflow parsing \"{s}\" as a {}.", .{ value, Size }, location),
                    error.InvalidCharacter => return self.createFormattedError(Errors.InvalidNumber, "Invalid number, \"{s}\".", .{value}, location),
                }
            };
        }

        fn errorFromGeneratorError(self: *Self, generatorError: anyerror, comptime template: []const u8, args: anytype, location: ?Location) LexerErrors {
            return self.createFormattedError(Errors.GeneratorError, "[{}]:{d}:{d} " ++ template, .{ generatorError, location.?.line, location.?.column } ++ args, location);
        }

        fn createError(self: *Self, errorType: Errors, message: []const u8, location: ?Location) LexerErrors {
            self.err = .{ .err = errorType, .message = message, .location = location };
            return errorType;
        }

        fn createFormattedError(self: *Self, errorType: Errors, comptime template: []const u8, args: anytype, location: ?Location) LexerErrors {
            var message = std.fmt.allocPrint(self.allocator, template, args) catch {
                return self.createError(Errors.InternalException, "Out of memory while building error message.", location);
            };
            self.err = .{ .err = errorType, .message = message, .location = location };
            return errorType;
        }
    };
}
