const std = @import("std");
const lexer = @import("../../lexer/lexer.zig");
const tokenizer = @import("../../tokenizer/tokenizer.zig");
const Errors = @import("../x86_64Generator.zig").Errors;
const GeneratorErrors = @import("../x86_64Generator.zig").GeneratorErrors;
const cpu = @import("../../cpu/cpu.zig");
const utils = @import("../utils.zig");
const generator = @import("../x86_64Generator.zig");
const x86_64CPU = @import("../../cpu/x86_64Cpu.zig");
const x86_64Cpu = x86_64CPU.x86_64Cpu;
const x86_64Register = x86_64CPU.Register;
const x86_64Registers = x86_64CPU.x86_64Registers;
const Self = generator.x86_64Generator.Self;

pub fn emitAssignment(self: *Self, leftValue: lexer.Operand, rightValue: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
    if (leftValue.accessType == .direct and @as(lexer.ValueType, leftValue.value) == .identifier) {
        try emitRegisterAssignment(self, leftValue, rightValue, location);
    } else if (leftValue.accessType == .indirect and @as(lexer.ValueType, leftValue.value) == .constant) {
        try emitMemoryAssignment(self, leftValue, rightValue, location);
    }
}

fn emitRegisterAssignment(self: *Self, leftValue: lexer.Operand, rightValue: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
    const sourceRegister = self.cpu.resolveRegister(leftValue.value.identifier) orelse return Errors.InternalException;
    const rightValueBits: cpu.BitSizes = switch (rightValue.value) {
        .constant => try self.countBits(rightValue.value.constant, location),
        .identifier => self.cpu.resolveRegister(rightValue.value.identifier).?.size,
    };

    if (@intFromEnum(rightValueBits) > @intFromEnum(sourceRegister.size)) {
        return Errors.InternalException;
    }

    if (rightValue.accessType == .direct and @as(lexer.ValueType, rightValue.value) == .constant) {
        try emitRegisterAssignmentImmediate(self, sourceRegister, rightValue, location);
    } else if (rightValue.accessType == .direct and @as(lexer.ValueType, rightValue.value) == .identifier) {
        try emitRegisterAssignmentRegister(self, sourceRegister, rightValue, location);
    } else if (rightValue.accessType == .indirect and @as(lexer.ValueType, rightValue.value) == .constant) {
        try emitRegisterAssignmentMemory(self, sourceRegister, rightValue, location);
    } else if (rightValue.accessType == .indirect and @as(lexer.ValueType, rightValue.value) == .identifier) {
        try emitRegisterAssignmentRegisterOffset(self, sourceRegister, rightValue, location);
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
