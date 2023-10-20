const std = @import("std");
const BufferedReader = std.io.BufferedReader;
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const u8util = @import("../util/u8util.zig");

const Errors = error{ ReaderError, InvalidIdentifier, InvalidString, InvalidNumber, InvalidSymbol, InvalidMultilineComment, InternalError };
pub const TokenizerErrors = Errors;
pub const TokenizerError = struct { err: Errors, message: []const u8, location: Location };
pub const Location = struct { location: usize = 0, line: usize = 0, column: usize = 0 };
pub const TokenType = enum {
    Literal,
    Identifier,
    Number,
    SymbolAt,
    SymbolAsterisk,
    SymbolColon,
    SymbolComma,
    SymbolDoubleQuote,
    SymbolEquals,
    SymbolForwardSlash,
    SymbolLeftParanthesis,
    SymbolMinus,
    SymbolPlus,
    SymbolRightParanthesis,
    SymbolSemicolon,
    ReservedBytes,
    ReservedCurrent,
    ReservedDoubleWords,
    ReservedQuadWords,
    ReservedPadBytes,
    ReservedSetBitMode,
    ReservedSetOrigin,
    ReservedStart,
    ReservedWords,
    InstructionJmp,
    NewLine,
    EOF,
};
pub const Token = struct {
    const Self = @This();

    location: Location,
    lexeme: []const u8,
    type: TokenType,
    allocator: ?Allocator = null,

    pub fn clone(self: Self, allocator: Allocator, err: *?TokenizerError) TokenizerErrors!Token {
        const lexeme = allocator.alloc(u8, self.lexeme.len) catch {
            err.* = .{ .err = Errors.InternalError, .message = "Out of memory.", .location = self.location };
            return Errors.InternalError;
        };
        std.mem.copy(u8, lexeme, self.lexeme);
        return .{ .type = self.type, .lexeme = lexeme, .location = self.location, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        if (self.allocator) |allocator| {
            allocator.free(self.lexeme);
        }
    }
};

pub const TokenEof = Token{ .location = .{}, .lexeme = "<EOF>", .type = .EOF };
const SymbolEquals: u8 = '=';
const SymbolAsterisk: u8 = '*';
const SymbolAt: u8 = '@';
const SymbolPlus: u8 = '+';
const SymbolMinus: u8 = '-';
const SymbolComma: u8 = ',';
const SymbolColon: u8 = ':';
const SymbolForwardSlash: u8 = '/';
const SymbolNewLine: u8 = '\n';
const SymbolDoubleQuote: u8 = '\"';
const SymbolLeftParanthesis: u8 = '(';
const SymbolRightParanthesis: u8 = ')';
const SymbolSemicolon: u8 = ';';
const ReservedBytes: []const u8 = "Bytes";
const ReservedCurrent: []const u8 = "Current";
const ReservedDoubleWords: []const u8 = "DoubleWords";
const ReservedQuadWords: []const u8 = "QuadWords";
const ReservedPadBytes: []const u8 = "PadBytes";
const ReservedSetBitMode: []const u8 = "SetBitMode";
const ReservedSetOrigin: []const u8 = "SetOrigin";
const ReservedStart: []const u8 = "Origin";
const ReservedWords: []const u8 = "Words";
const InstructionJmp: []const u8 = "jmp";

const ByteClassification = struct {
    const Self = @This();

    alpha: bool = false,
    numeric: bool = false,
    hexDigit: bool = false,
    binaryDigit: bool = false,

    pub fn isAlpha(self: Self) bool {
        return self.alpha;
    }

    pub fn isNumeric(self: Self) bool {
        return self.numeric;
    }

    pub fn isAlphaNumeric(self: Self) bool {
        return self.alpha and self.numeric;
    }

    pub fn isHexDigit(self: Self) bool {
        return self.hexDigit;
    }

    pub fn isBinaryDigit(self: Self) bool {
        return self.binaryDigit;
    }

    pub fn isSymbol(self: Self) bool {
        return !self.isAlphaNumeric();
    }
};

pub fn tokenizer() type {
    return struct {
        const Self = @This();

        err: ?TokenizerError,
        file: File,
        fileReader: std.io.BufferedReader(4096, File.Reader),
        allocator: Allocator,
        location: Location = Location{},
        nextByte: ?u8 = null,
        buffer: [4096]u8 = undefined,
        isEndOfFile: bool = false,
        symbols: std.AutoHashMap(u8, TokenType),
        reservedWords: std.StringHashMap(TokenType),
        instructions: std.StringHashMap(TokenType),

        pub fn init(filePath: []const u8, allocator: Allocator, err: *?TokenizerError) anyerror!Self {
            const file = try std.fs.openFileAbsolute(filePath, .{ .mode = .read_only });
            var fileReader = std.io.bufferedReader(file.reader());
            err.* = null;
            var symbols = std.AutoHashMap(u8, TokenType).init(allocator);
            try symbols.put(SymbolEquals, .SymbolEquals);
            try symbols.put(SymbolAsterisk, .SymbolAsterisk);
            try symbols.put(SymbolAt, .SymbolAt);
            try symbols.put(SymbolPlus, .SymbolPlus);
            try symbols.put(SymbolMinus, .SymbolMinus);
            try symbols.put(SymbolComma, .SymbolComma);
            try symbols.put(SymbolColon, .SymbolColon);
            try symbols.put(SymbolForwardSlash, .SymbolForwardSlash);
            try symbols.put(SymbolNewLine, .NewLine);
            try symbols.put(SymbolDoubleQuote, .SymbolDoubleQuote);
            try symbols.put(SymbolLeftParanthesis, .SymbolLeftParanthesis);
            try symbols.put(SymbolRightParanthesis, .SymbolRightParanthesis);
            try symbols.put(SymbolSemicolon, .SymbolSemicolon);
            var reservedWords = std.StringHashMap(TokenType).init(allocator);
            try reservedWords.put(ReservedBytes, .ReservedBytes);
            try reservedWords.put(ReservedCurrent, .ReservedCurrent);
            try reservedWords.put(ReservedDoubleWords, .ReservedDoubleWords);
            try reservedWords.put(ReservedPadBytes, .ReservedPadBytes);
            try reservedWords.put(ReservedQuadWords, .ReservedQuadWords);
            try reservedWords.put(ReservedSetBitMode, .ReservedSetBitMode);
            try reservedWords.put(ReservedSetOrigin, .ReservedSetOrigin);
            try reservedWords.put(ReservedStart, .ReservedStart);
            try reservedWords.put(ReservedWords, .ReservedWords);
            var instructions = std.StringHashMap(TokenType).init(allocator);
            try instructions.put(InstructionJmp, .InstructionJmp);
            return .{
                .err = null,
                .file = file,
                .fileReader = fileReader,
                .allocator = allocator,
                .symbols = symbols,
                .reservedWords = reservedWords,
                .instructions = instructions,
            };
        }

        pub fn deinit(self: *Self) void {
            self.file.close();
            self.symbols.deinit();
            self.reservedWords.deinit();
            self.instructions.deinit();
        }

        pub fn reinit(self: *Self) TokenizerErrors!void {
            self.file.seekTo(0) catch return self.createError(Errors.InternalError, "Failed to seek to file beginning.", &self.err);
            self.fileReader = std.io.bufferedReader(self.file.reader());
            self.nextByte = null;
            self.isEndOfFile = false;
        }

        pub fn next(self: *Self, err: *?TokenizerError) TokenizerErrors!Token {
            if (self.isEndOfFile) return TokenEof;

            var reader = self.fileReader.reader();

            while (true) {
                const byte = try self.peekByte(reader, err);
                if (byte) |peek| {
                    var token: Token = undefined;
                    try self.skip(reader, " \r\t", err);
                    if (peek == SymbolNewLine) {
                        self.buffer[0] = (try self.readByte(reader, err)).?;
                        token = self.createToken(.NewLine, self.buffer[0..1]);
                    } else if (peek == SymbolDoubleQuote) {
                        token = try self.readStringLiteral(reader, err);
                    } else if (peek == SymbolSemicolon) {
                        try self.readComment(reader, err);
                        continue;
                    } else if (peek == SymbolForwardSlash) {
                        try self.skipByte(reader, err);
                        if (try self.peekByte(reader, err)) |pb2| {
                            if (pb2 == SymbolForwardSlash or pb2 == SymbolAsterisk) {
                                try self.readComment(reader, err);
                                continue;
                            } else {
                                token = try self.readSymbol(reader, err);
                            }
                        } else {
                            token = try self.readSymbol(reader, err);
                        }
                        _ = try self.readComment(reader, err);
                        continue;
                    } else if (u8util.isAlpha(peek)) {
                        token = try self.readIdentifier(reader, err);
                    } else if (u8util.isNumeric(peek)) {
                        token = try self.readNumber(reader, err);
                    } else {
                        token = try self.readSymbol(reader, err);
                    }
                    try self.skip(reader, " \r\t", err);
                    return try token.clone(self.allocator, err);
                } else {
                    // EOF
                    break;
                }
            }

            return TokenEof;
        }

        fn readNumber(self: *Self, reader: anytype, err: *?TokenizerError) TokenizerErrors!Token {
            err.* = null;

            var pos: u8 = 0;
            var isHex = false;
            var isBinary = false;
            while (true) {
                const byte = try self.peekByte(reader, err);
                if (byte) |pb| {
                    if (pos == 1 and (pb == 'b' or pb == 'x')) {
                        // Pass
                        isHex = pb == 'x';
                        isBinary = pb == 'b';
                        // } else if (pb == ',' or pb == '_') {
                        //     // Peek was already a number
                        //     if (pos == 0) unreachable;
                        //     if (self.buffer[pos - 1] == ',' or self.buffer[pos - 1] == '_')
                        //         return self.createError(Errors.InvalidNumber, "Cannot use multiple number separators in a row.", err);
                    } else if (!u8util.isNumeric(pb) and !(isHex and u8util.isHexDigit(pb)) and !(isBinary and u8util.isBinaryDigit(pb))) {
                        return self.createToken(.Number, self.buffer[0..pos]);
                    }

                    self.buffer[pos] = (try self.readByte(reader, err)).?;
                    pos += 1;
                } else {
                    // Presumably EOF
                    break;
                }
            }

            if (pos == 0) unreachable;
            return self.createToken(.Number, self.buffer[0..pos]);
        }

        fn readStringLiteral(self: *Self, reader: anytype, err: *?TokenizerError) TokenizerErrors!Token {
            err.* = null;
            var pos: u8 = 0;
            try self.skipByte(reader, err);

            // Check for multiline
            var isMultiline = false;
            if (try self.peekByte(reader, err)) |pb1| {
                if (pb1 == '"') {
                    try self.skipByte(reader, err);
                    if (try self.peekByte(reader, err)) |pb2| {
                        if (pb2 == '"') {
                            isMultiline = true;
                            try self.skipByte(reader, err);
                        } else {
                            // "", so empty string
                            return self.createToken(.Literal, self.buffer[0..2]);
                        }
                    }
                }
            }

            var escapeCount: u8 = 0;
            var quoteCount: u8 = 0;

            while (true) {
                const byte = try self.peekByte(reader, err);
                if (byte) |pb| {
                    self.buffer[pos] = (try self.readByte(reader, err)).?;
                    pos += 1;

                    if (isMultiline) {
                        if (pb == '"') {
                            if (self.buffer[pos - 1] == '"') {
                                quoteCount += 1;
                            } else {
                                quoteCount = 1;
                            }
                            if (quoteCount == 3) {
                                return self.createToken(.Literal, self.buffer[0..(pos - 3)]);
                            }
                        } else {
                            quoteCount = 0;
                        }
                    } else {
                        if (pb == '\\') {
                            escapeCount += 1;
                        } else if (pb == '\"' and escapeCount % 2 == 0) {
                            return self.createToken(.Literal, self.buffer[0..(pos - 1)]);
                        } else if (pb == '\n') {
                            // Found a new line before a closing "
                            break;
                        }
                    }
                } else {
                    // EOF
                    break;
                }
            }

            if (isMultiline) {
                return self.createError(Errors.InvalidString, "Multiline string missing closing \"\"\".", err);
            } else {
                return self.createError(Errors.InvalidString, "String missing closing \".", err);
            }
        }

        fn readComment(self: *Self, reader: anytype, err: *?TokenizerError) TokenizerErrors!void {
            err.* = null;

            // Check for multiline
            var isMultiline = false;
            if (try self.peekByte(reader, err)) |pb| {
                isMultiline = pb == SymbolAsterisk;
                try self.skipByte(reader, err);
            } else {
                unreachable;
            }

            while (true) {
                var byte = try self.peekByte(reader, err);
                if (byte) |pb1| {
                    if (isMultiline) {
                        if (pb1 == SymbolAsterisk) {
                            try self.skipByte(reader, err);
                            byte = try self.peekByte(reader, err);
                            if (byte) |pb2| {
                                if (pb2 == SymbolForwardSlash) {
                                    try self.skipByte(reader, err);
                                    return;
                                }
                            }
                        }
                    } else if (pb1 == '\n') {
                        try self.skipByte(reader, err);
                        return;
                    }
                    try self.skipByte(reader, err);
                } else {
                    // EOF
                    if (isMultiline) {
                        return Errors.InvalidMultilineComment;
                    }
                    break;
                }
            }
        }

        fn readIdentifier(self: *Self, reader: anytype, err: *?TokenizerError) TokenizerErrors!Token {
            err.* = null;
            var pos: u8 = 0;
            while (true) {
                const byte = try self.peekByte(reader, err);
                if (byte) |pb| {
                    if (!u8util.isAlphaNumeric(pb)) {
                        if (pos == 0) {
                            // Shouldn't be possible as we check the first character going in
                            unreachable;
                        } else {
                            // Next token
                            break;
                        }
                    }
                    self.buffer[pos] = (try self.readByte(reader, err)).?;
                    pos += 1;
                } else {
                    // Probably EOF
                    break;
                }
            }

            if (pos == 0) unreachable;

            var lexeme = self.buffer[0..pos];
            if (self.reservedWords.contains(lexeme)) {
                return self.createToken(self.reservedWords.get(lexeme).?, lexeme);
            }

            var lowerBuffer = self.allocator.alloc(u8, pos) catch return self.createError(Errors.InternalError, "Failed to allocated space for lower-case instruction check.", err);
            defer self.allocator.free(lowerBuffer);
            _ = std.ascii.lowerString(lowerBuffer, self.buffer[0..pos]);
            if (self.instructions.contains(lowerBuffer)) {
                return self.createToken(self.instructions.get(lowerBuffer).?, lexeme);
            }

            return self.createToken(.Identifier, lexeme);
        }

        fn readSymbol(self: *Self, reader: anytype, err: *?TokenizerError) Errors!Token {
            err.* = null;
            const byte = try self.readByte(reader, err);
            if (byte) |pb| {
                if (self.symbols.contains(pb)) {
                    self.buffer[0] = pb;
                    return self.createToken(self.symbols.get(pb).?, self.buffer[0..1]);
                }
            }

            return self.createError(TokenizerErrors.InvalidSymbol, "Invalid symbol.", err);
        }

        fn skipByte(self: *Self, reader: anytype, err: *?TokenizerError) Errors!void {
            _ = self.readByte(reader, err) catch {};
        }

        fn skip(self: *Self, reader: anytype, characters: []const u8, err: *?TokenizerError) Errors!void {
            err.* = null;
            while (true) {
                const byte = try self.peekByte(reader, err);
                if (byte) |pb| {
                    for (characters) |ch| {
                        if (pb == ch) {
                            _ = try self.readByte(reader, err);
                            continue;
                        }
                    }
                    // Non-matching character
                    break;
                } else {
                    // EOF
                    break;
                }
            }
        }

        fn peekByte(self: *Self, reader: anytype, err: *?TokenizerError) Errors!?u8 {
            _ = err;
            if (self.nextByte) |pb| {
                return pb;
            }

            self.nextByte = try _readByte(reader);
            return self.nextByte;
        }

        fn readByte(self: *Self, reader: anytype, err: *?TokenizerError) Errors!?u8 {
            _ = err;
            var byte: ?u8 = undefined;
            if (self.nextByte) |pb| {
                defer self.nextByte = null;
                byte = pb;
            } else if (_readByte(reader)) |rb| {
                byte = rb;
            } else |e| {
                // err = .{ .err = e };
                return e;
            }

            self.location.location += 1;
            if (byte == '\n') {
                self.location.line += 1;
                self.location.column = 0;
            }

            return byte;
        }

        fn _readByte(reader: anytype) Errors!?u8 {
            return reader.readByte() catch null;
        }

        fn createToken(self: Self, tokenType: TokenType, lexeme: []const u8) Token {
            return .{ .location = self.location, .type = tokenType, .lexeme = lexeme };
        }

        fn createError(self: Self, errorType: Errors, message: []const u8, err: *?TokenizerError) TokenizerErrors {
            err.* = .{ .err = errorType, .message = message, .location = self.location };
            return errorType;
        }
    };
}
