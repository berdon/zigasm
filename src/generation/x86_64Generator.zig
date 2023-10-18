const std = @import("std");
const tokenizer = @import("../tokenizer/tokenizer.zig");
const lexer = @import("../lexer/lexer.zig");
const CPU = @import("../cpu/cpu.zig");
const x86_64CPU = @import("../cpu/x86_64Cpu.zig");
const x86_64Cpu = x86_64CPU.x86_64Cpu;
const x86_64Register = x86_64CPU.Register;
const x86_64Registers = x86_64CPU.x86_64Registers;
const JMP = @import("./instructions/jmp.zig");

pub const Errors = error{ InternalException, RegisterNotSupportedInBitMode };
pub const GeneratorErrors = Errors;
pub const GeneratorError = struct {
    err: GeneratorErrors,
    message: []const u8,
    location: ?tokenizer.Location,
};
pub const Symbol = struct {
    name: []const u8,
    address: usize,
};
const WriterType = std.fs.File.Writer;
const x86_64CpuType = x86_64Cpu();

pub const x86_64Generator = struct {
    const Self = @This();

    addressCounter: usize = 0,
    addressOrigin: usize = 0,
    allocator: std.mem.Allocator = undefined,
    availableExtensions: []const x86_64CPU.Extensions = &[_]x86_64CPU.Extensions{},
    bitMode: CPU.BitModes = .Bit16,
    cpu: *x86_64CpuType,
    err: ?GeneratorError = undefined,
    filePath: []const u8,
    file: ?std.fs.File = null,
    labels: std.StringHashMap(Symbol) = undefined,
    writer: ?WriterType = null,

    pub fn init(allocator: std.mem.Allocator, cpu: *x86_64CpuType, filePath: []const u8) Self {
        var result = Self{
            .filePath = filePath,
            .allocator = allocator,
            .cpu = cpu,
        };
        result.labels = @TypeOf(result.labels).init(allocator);
        return result;
    }

    pub fn getCpuType() type {
        return x86_64CpuType;
    }

    pub fn deinit(self: *Self) void {
        for (self.labels.valueIterator().next()) |value| self.allocator.free(value.name);
        self.labels.deinit();
        if (self.file) |file| {
            file.close();
        }
    }

    fn getWriter(self: *Self) Errors!WriterType {
        if (self.writer) |writer| {
            return writer;
        }
        self.file = std.fs.createFileAbsolute(self.filePath, .{ .read = true }) catch {
            return GeneratorErrors.InternalException;
        };
        self.writer = self.file.?.writer();
        return self.writer.?;
    }

    pub fn processLabel(self: *Self, label: tokenizer.Token) anyerror!void {
        var nameBuffer = try self.allocator.alloc(u8, label.lexeme.len);
        std.mem.copy(u8, nameBuffer, label.lexeme);
        try self.labels.put(label.lexeme, .{ .name = nameBuffer, .address = self.addressCounter });
    }

    pub fn processRawInstruction(self: *Self, mnemonic: tokenizer.Token, operands: std.ArrayList(lexer.Operand)) GeneratorErrors!void {
        _ = operands;
        _ = mnemonic;
        _ = self;
    }

    pub fn processSetBitModeDirective(self: *Self, bitMode: CPU.BitModes) GeneratorErrors!void {
        self.bitMode = bitMode;
    }

    pub fn processSetOriginDirective(self: *Self, origin: usize) GeneratorErrors!void {
        self.addressOrigin = origin;
    }

    pub fn emitBytes(self: *Self, bytes: []const u8) GeneratorErrors!void {
        _ = (try self.getWriter()).write(bytes) catch return self.createError(Errors.InternalException, "Failed emitting bytes.", null);
        self.addressCounter += bytes.len;
    }

    pub fn emitAssignment(self: *Self, leftValue: lexer.Operand, rightValue: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
        if (leftValue.accessType == .direct and @as(lexer.ValueType, leftValue.value) == .identifier) {
            try self.emitRegisterAssignment(leftValue, rightValue, location);
        } else if (leftValue.accessType == .indirect and @as(lexer.ValueType, leftValue.value) == .constant) {
            try self.emitMemoryAssignment(leftValue, rightValue, location);
        }
    }

    pub fn emitJump(self: *Self, operand: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
        return JMP.emitJump(self, operand, location);
    }

    fn emitRegisterAssignment(self: *Self, leftValue: lexer.Operand, rightValue: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
        const sourceRegister = self.cpu.resolveRegister(leftValue.value.identifier) orelse return Errors.InternalException;
        const rightValueBits: CPU.BitSizes = switch (rightValue.value) {
            .constant => try self.countBits(rightValue.value.constant, location),
            .identifier => self.cpu.resolveRegister(rightValue.value.identifier).?.size,
        };

        if (@intFromEnum(rightValueBits) > @intFromEnum(sourceRegister.size)) {
            return Errors.InternalException;
        }

        if (rightValue.accessType == .direct and @as(lexer.ValueType, rightValue.value) == .constant) {
            try self.emitRegisterAssignmentImmediate(sourceRegister, rightValue, location);
        } else if (rightValue.accessType == .direct and @as(lexer.ValueType, rightValue.value) == .identifier) {
            try self.emitRegisterAssignmentRegister(sourceRegister, rightValue, location);
        } else if (rightValue.accessType == .indirect and @as(lexer.ValueType, rightValue.value) == .constant) {
            try self.emitRegisterAssignmentMemory(sourceRegister, rightValue, location);
        } else if (rightValue.accessType == .indirect and @as(lexer.ValueType, rightValue.value) == .identifier) {
            try self.emitRegisterAssignmentRegisterOffset(sourceRegister, rightValue, location);
        }
    }

    fn emitMemoryAssignment(self: *Self, leftValue: lexer.Operand, rightValue: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
        _ = location;
        _ = rightValue;
        _ = leftValue;
        _ = self;
    }

    fn emitRegisterAssignmentImmediate(self: *Self, destination: x86_64Register, rightValue: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
        if (!destination.supportedByBitMode(self.bitMode)) {
            return self.createFormattedError(
                Errors.RegisterNotSupportedInBitMode,
                "Register ({s}) not supported in bit mode {} at {d}:{d}.",
                .{ destination.name, self.bitMode, location.line, location.column },
                location,
            );
        }

        switch (destination.size) {
            .Bits8 => {
                var valueBuffer = try self.bytesFromValue(rightValue.value.constant, 1, location);
                defer self.allocator.free(valueBuffer);

                var result = std.mem.concat(self.allocator, u8, &[_][]const u8{
                    &[_]u8{@intCast(0xB0 + (destination.registerIndex orelse unreachable))},
                    valueBuffer,
                }) catch {
                    return self.createError(Errors.InternalException, "Failed to combine slices.", location);
                };
                defer self.allocator.free(result);
                try self.emitBytes(result);
            },
            .Bits16 => {
                var valueBuffer = try self.bytesFromValue(rightValue.value.constant, 2, location);
                defer self.allocator.free(valueBuffer);

                var result = std.mem.concat(self.allocator, u8, &[_][]const u8{
                    &[_]u8{@intCast(0xB8 + (destination.registerIndex orelse unreachable))},
                    valueBuffer,
                }) catch {
                    return self.createError(Errors.InternalException, "Failed to combine slices.", location);
                };
                defer self.allocator.free(result);
                try self.emitBytes(result);
            },
            .Bits32 => {
                var valueBuffer = try self.bytesFromValue(rightValue.value.constant, 4, location);
                defer self.allocator.free(valueBuffer);

                var result = std.mem.concat(self.allocator, u8, &[_][]const u8{
                    &(if (self.bitMode == .Bit16) [_]u8{0x66} else [_]u8{}),
                    &[_]u8{@intCast(0xB8 + (destination.registerIndex orelse unreachable))},
                    valueBuffer,
                }) catch {
                    return self.createError(Errors.InternalException, "Failed to combine slices.", location);
                };
                defer self.allocator.free(result);
                try self.emitBytes(result);
            },
            else => unreachable,
        }
    }

    fn emitRegisterAssignmentRegister(self: *Self, destination: x86_64Register, rightValue: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
        _ = location;
        _ = rightValue;
        _ = destination;
        _ = self;
    }

    fn emitRegisterAssignmentMemory(self: *Self, destination: x86_64Register, rightValue: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
        _ = location;
        _ = rightValue;
        _ = destination;
        _ = self;
    }

    fn emitRegisterAssignmentRegisterOffset(self: *Self, destination: x86_64Register, rightValue: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
        _ = location;
        _ = rightValue;
        _ = destination;
        _ = self;
    }

    pub fn countBytes(self: *Self, value: []const u8, location: tokenizer.Location) GeneratorErrors!usize {
        if (value.len == 0) unreachable;
        var bytes: usize = 0;
        if (value.len > 2) {
            if (std.mem.eql(u8, value[0..2], "0x")) {
                bytes = (value.len - 2 + (value.len % 2)) / 2;
            } else if (std.mem.eql(u8, value[0..2], "0b")) {
                bytes = (value.len - 2 + (value.len % 8)) / 7;
            }
        } else {
            var actualValue = std.fmt.parseInt(usize, value, 0) catch {
                return self.createFormattedError(Errors.InternalException, "Invalid number \"{s}\".", .{value}, location);
            };
            var bits: usize = 8;
            while (std.math.pow(usize, 2, bits) < actualValue) {
                bits *= 2;
            }
            bytes = bits / 2;
        }

        return bytes;
    }

    pub fn countBits(self: *Self, value: []const u8, location: tokenizer.Location) GeneratorErrors!CPU.BitSizes {
        const bytes = try self.countBytes(value, location);
        return CPU.bitSizeFromBytes(bytes);
    }

    pub fn bytesFromValue(self: *Self, value: []const u8, byteCount: usize, location: tokenizer.Location) GeneratorErrors![]const u8 {
        if (value.len == 0) unreachable;
        var requiredBytes = try self.countBytes(value, location);
        if (requiredBytes > byteCount) {
            return self.createFormattedError(Errors.InternalException, "Value ({s}) exceeds register size ({d}).", .{ value, byteCount }, location);
        }
        if (value.len > 2) {
            if (std.mem.eql(u8, value[0..2], "0x")) {
                var buffer = self.allocator.alloc(u8, byteCount) catch {
                    return self.createFormattedError(Errors.InternalException, "Out of memory try in bytesFromValue.", .{}, location);
                };
                for (0..buffer.len) |i| buffer[i] = 0;
                var i: usize = buffer.len;
                var strictValue = value[2..value.len];
                var nextByte: u8 = 0;
                for (0..strictValue.len) |j| {
                    // for (strictValue) |byte| {
                    var byte = strictValue[strictValue.len - 1 - j];
                    var tempByte: u8 = 0;
                    if (byte >= '0' and byte <= '9') tempByte = byte - 48;
                    if (byte >= 'A' and byte <= 'F') tempByte = byte - 55;
                    if (byte >= 'a' and byte <= 'f') tempByte = byte - 87;

                    if (j % 2 == 0) {
                        nextByte = tempByte;
                    } else {
                        buffer[i - 1] = nextByte | (tempByte << 4);
                        nextByte = 0;
                        i -= 1;
                    }
                }
                if (nextByte != 0 and i > 0) {
                    buffer[i - 1] = nextByte;
                }
                std.mem.reverse(u8, buffer);
                return buffer;
            } else if (std.mem.eql(u8, value[0..2], "0b")) {
                // TODO: Implement
                unreachable;
            }
        } else {
            var actualValue = std.fmt.parseInt(usize, value, 0) catch {
                return self.createFormattedError(Errors.InternalException, "Invalid number \"{s}\".", .{value}, location);
            };
            var temp = std.fmt.allocPrint(self.allocator, "0x{X}", .{actualValue}) catch {
                return self.createError(Errors.InternalException, "Out of memory trying to generate error message.", location);
            };
            return try self.bytesFromValue(temp, byteCount, location);
        }

        unreachable;
    }

    pub fn getValueSizeFromBitMode(self: Self) u8 {
        return switch (self.bitMode) {
            .Bit16 => 2,
            .Bit32 => 4,
            .Bit64 => 8,
        };
    }

    pub fn createError(self: *Self, err: GeneratorErrors, message: []const u8, location: ?tokenizer.Location) GeneratorErrors {
        self.err = .{
            .err = err,
            .message = message,
            .location = location,
        };
        return err;
    }

    pub fn createFormattedError(self: *Self, errorType: Errors, comptime template: []const u8, args: anytype, location: ?tokenizer.Location) GeneratorErrors {
        var message = std.fmt.allocPrint(self.allocator, template, args) catch {
            return self.createError(Errors.InternalException, "Out of memory while building error message.", location);
        };
        self.err = .{ .err = errorType, .message = message, .location = location };
        return errorType;
    }
};
