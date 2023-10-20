const CPU = @import("../cpu/cpu.zig");
const JMP = @import("./instructions/jmp.zig");
const MOV = @import("./instructions/mov.zig");
const lexer = @import("../lexer/lexer.zig");
const std = @import("std");
const tokenizer = @import("../tokenizer/tokenizer.zig");
const utils = @import("./utils.zig");
const x86_64CPU = @import("../cpu/x86_64Cpu.zig");
const x86_64Cpu = x86_64CPU.x86_64Cpu;
const x86_64Register = x86_64CPU.Register;
const x86_64Registers = x86_64CPU.x86_64Registers;

pub const Errors = error{ InternalException, RegisterNotSupportedInBitMode, InvalidParsingPass };
pub const GeneratorErrors = Errors;
pub const GeneratorError = struct {
    err: GeneratorErrors,
    message: []const u8,
    location: ?tokenizer.Location,
};
pub const ParsingPasses = enum(u1) {
    FirstPass = 0,
    SecondPass,
};
pub const PendingJump = struct { address: usize, size: u8, target: Symbol };
pub const Symbol = struct {
    name: []const u8,
    address: ?usize,
};
const WriterType = std.fs.File.Writer;
const x86_64CpuType = x86_64Cpu();

pub const x86_64Generator = struct {
    pub const Self = @This();

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
    parsingPass: ParsingPasses = .FirstPass,
    pendingJumps: std.ArrayList(PendingJump) = undefined,
    writer: ?WriterType = null,

    pub fn init(allocator: std.mem.Allocator, cpu: *x86_64CpuType, filePath: []const u8) Self {
        var result = Self{
            .filePath = filePath,
            .allocator = allocator,
            .cpu = cpu,
        };
        result.labels = @TypeOf(result.labels).init(allocator);
        result.pendingJumps = @TypeOf(result.pendingJumps).init(allocator);
        return result;
    }

    pub fn getCpuType() type {
        return x86_64CpuType;
    }

    pub fn nextPass(self: *Self) GeneratorErrors!void {
        switch (self.parsingPass) {
            .FirstPass => try self.finalizeFirstPass(),
            .SecondPass => return self.createFormattedError(Errors.InvalidParsingPass, "There are only two parsing passes.", .{}, null),
        }
        self.parsingPass = @enumFromInt(@intFromEnum(self.parsingPass) + 1);
        self.addressOrigin = 0;
        self.addressCounter = 0;
        self.err = null;
        self.bitMode = .Bit16;
    }

    pub fn deinit(self: *Self) void {
        for (self.labels.valueIterator().next()) |value| self.allocator.free(value.name);
        self.labels.deinit();
        self.pendingJumps.deinit();
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

    pub fn currentAddress(self: *Self) usize {
        return self.addressOrigin + self.addressCounter;
    }

    pub fn hasSymbol(self: Self, name: []const u8) bool {
        return self.labels.contains(name);
    }

    pub fn getSymbol(self: Self, name: []const u8) ?Symbol {
        return self.labels.get(name);
    }

    pub fn putSymbol(self: *Self, name: []const u8, address: ?usize, location: ?tokenizer.Location) GeneratorErrors!Symbol {
        var nameBuffer = self.allocator.alloc(u8, name.len) catch {
            return self.createFormattedError(Errors.InternalException, "Failed to allocate memory for a symbol name, \"{s}\".", .{name}, location);
        };
        std.mem.copy(u8, nameBuffer, name);
        self.labels.put(nameBuffer, .{ .name = nameBuffer, .address = address }) catch {
            return self.createFormattedError(Errors.InternalException, "Failed to allocate memory for a symbol name, \"{s}\".", .{name}, location);
        };
        return self.labels.get(name).?;
    }

    pub fn processLabel(self: *Self, name: []const u8, location: ?tokenizer.Location) GeneratorErrors!void {
        _ = try self.putSymbol(name, self.addressOrigin + self.addressCounter, location);
    }

    pub fn recordPendingJump(self: *Self, address: usize, target: Symbol, size: u8, location: tokenizer.Location) GeneratorErrors!void {
        self.pendingJumps.append(.{ .address = address, .size = size, .target = target }) catch {
            return self.createFormattedError(Errors.InternalException, "Failed to allocate memory for pending jump from {d} to \"{s}\".", .{ address, target.name }, location);
        };
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

    pub fn processPadBytesDirective(self: *Self, size: usize, byte: u8) GeneratorErrors!void {
        for (0..size) |_| try self.emitBytes(&[1]u8{byte});
    }

    pub fn finalizeFirstPass(self: *Self) GeneratorErrors!void {
        // Iterate through each pending jump and determine the worst case sizing then adjust the
        // size and decrement the addresses of all proceeding symbols
        for (self.pendingJumps.items) |*pendingJump| {
            var originalSize = pendingJump.size;
            pendingJump.size = try self.getWorstCaseJumpSize(pendingJump.*);
            var valueIterator = self.labels.valueIterator();
            while (valueIterator.next()) |label| {
                if (label.address.? >= (pendingJump.address + originalSize)) {
                    label.address = label.address.? - (originalSize - pendingJump.size);
                }
            }
        }
    }

    fn getWorstCaseJumpSize(self: *Self, pendingJump: PendingJump) GeneratorErrors!u8 {
        if (self.labels.get(pendingJump.target.name)) |target| {
            var targetAddress: isize = @intCast(target.address.?);
            var pendingJumpAddress: isize = @intCast(pendingJump.address);
            return utils.requiredBytesForSignedInteger(targetAddress - pendingJumpAddress);
        } else {
            return self.createFormattedError(Errors.InternalException, "Invalid or unknown target for jump, \"{s}\".", .{pendingJump.target.name}, null);
        }
    }

    pub fn emitBytes(self: *Self, bytes: []const u8) GeneratorErrors!void {
        if (self.parsingPass == .SecondPass) {
            _ = (try self.getWriter()).write(bytes) catch return self.createError(Errors.InternalException, "Failed emitting bytes.", null);
        }

        self.addressCounter += bytes.len;
    }

    pub fn emitDoubleWord(self: *Self, value: u32) GeneratorErrors!void {
        try self.emitBytes(&[2]u8{ @intCast(value & 0xFF), @intCast(value >> 8) });
    }

    pub fn emitJump(self: *Self, operand: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
        return JMP.emitJump(self, operand, location);
    }

    pub fn emitAssignment(self: *Self, leftValue: lexer.Operand, rightValue: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
        return MOV.emitAssignment(self, leftValue, rightValue, location);
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
