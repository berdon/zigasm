const std = @import("std");
const BufferedReader = std.io.BufferedReader;
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const u8util = @import("../util/u8util.zig");

const Errors = error{ ReaderError, InvalidIdentifier, InvalidString, InvalidNumber };

pub const TokenizerErrors = Errors;

pub const TokenizerError = struct { err: Errors, message: []const u8, location: Location };

pub const Location = struct { location: usize = 0, line: usize = 0, column: usize = 0 };

pub const TokenType = enum { Literal, Identifier, Number, Symbol, NewLine, EOF };

pub const Token = struct {
    const Self = @This();

    location: Location,
    lexeme: []const u8,
    type: TokenType,
    allocator: ?Allocator = null,

    pub fn clone(self: Self, allocator: Allocator) anyerror!Token {
        const lexeme = try allocator.alloc(u8, self.lexeme.len);
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

pub const Tokenizer = struct {
    const Self = @This();

    file: File,
    fileReader: std.io.BufferedReader(4096, File.Reader),
    allocator: Allocator,
    location: Location = Location{},
    nextByte: ?u8 = null,
    buffer: [4096]u8 = undefined,
    isEndOfFile: bool = false,

    pub fn deinit(self: *Self) noreturn {
        self.file.close();
        self.allocator.free(self.buffer);
    }

    pub fn next(self: *Self, err: *?TokenizerError) TokenizerErrors!Token {
        if (self.isEndOfFile) return TokenEof;

        var reader = self.fileReader.reader();

        const byte = try self.peekByte(reader, err);
        if (byte) |peek| {
            var token: Token = undefined;
            try self.skip(reader, " \r\t", err);
            if (peek == '\n') {
                self.buffer[0] = (try self.readByte(reader, err)).?;
                token = self.createToken(.NewLine, self.buffer[0..1]);
            } else if (peek == '\"') {
                token = try self.readStringLiteral(reader, err);
            } else if (peek == '\\') {
                // token = self.readComment(reader);
            } else if (u8util.isAlpha(peek)) {
                token = try self.readIdentifier(reader, err);
            } else if (u8util.isNumeric(peek)) {
                token = try self.readNumber(reader, err);
            } else {
                self.buffer[0] = (try self.readByte(reader, err)).?;
                token = self.createToken(.Symbol, self.buffer[0..1]);
            }
            try self.skip(reader, " \r\t", err);
            return token;
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
                } else if (pb == ',' or pb == '_') {
                    // Peek was already a number
                    if (pos == 0) unreachable;
                    if (self.buffer[pos - 1] == ',' or self.buffer[pos - 1] == '_')
                        return self.createError(Errors.InvalidNumber, "Cannot use multiple number separators in a row.", err);
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
        return self.createToken(.Identifier, self.buffer[0..pos]);
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

pub fn tokenizer(filePath: []const u8, allocator: Allocator, err: *?TokenizerError) anyerror!Tokenizer {
    const file = try std.fs.openFileAbsolute(filePath, .{ .mode = .read_only });
    var fileReader = std.io.bufferedReader(file.reader());
    err.* = null;
    // const buffer = try allocator.create([4096]u8);
    return .{ .file = file, .fileReader = fileReader, .allocator = allocator };
}
