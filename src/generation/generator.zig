const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const tokenizer = @import("../tokenizer/tokenizer.zig");
const CPU = @import("../cpu/cpu.zig");

const WriterType = std.fs.File.Writer;
const Errors = error{InternalException};
pub const GeneratorErrors = Errors;
pub const Symbol = struct {
    name: []const u8,
    address: usize,
};
pub fn generator(comptime GeneratorContextType: anytype) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator = undefined,
        generator: GeneratorContextType,
        filePath: []const u8,
        file: ?std.fs.File = null,
        writer: ?WriterType = null,
        labels: std.StringHashMap(Symbol) = undefined,

        pub fn init(allocator: std.mem.Allocator, cpu: anytype, filePath: []const u8) anyerror!Self {
            var result = Self{
                .allocator = allocator,
                .generator = undefined,
                .filePath = filePath,
            };
            result.generator = try GeneratorContextType.init(allocator, cpu);
            result.labels = @TypeOf(result.labels).init(allocator);
            return result;
        }

        pub fn deinit(self: *Self) void {
            self.generator.deinit();
            for (self.labels.valueIterator().next()) |value| self.allocator.free(value.name);
            self.labels.deinit();
            if (self.file) |file| {
                file.close();
            }
        }

        pub fn emitAssignment(self: *Self, leftValue: lexer.Operand, rightValue: lexer.Operand, location: tokenizer.Location) anyerror!void {
            var writer = try self.getWriter();
            try self.generator.emitAssignment(writer, leftValue, rightValue, location);
        }

        pub fn emitJump(self: *Self, operand: lexer.Operand, location: tokenizer.Location) anyerror!void {
            var writer = try self.getWriter();
            try self.generator.emitJump(writer, operand, location);
        }

        pub fn processLabel(self: *Self, label: tokenizer.Token) anyerror!void {
            var nameBuffer = try self.allocator.alloc(u8, label.lexeme.len);
            std.mem.copy(u8, nameBuffer, label.lexeme);
            try self.labels.put(label.lexeme, .{ .name = nameBuffer, .address = self.generator.addressCounter });
        }

        pub fn processRawInstruction(self: *Self, mnemonic: tokenizer.Token, operands: std.ArrayList(lexer.Operand)) anyerror!void {
            return self.generator.processRawInstruction(mnemonic, operands);
        }

        pub fn processSetBitModeDirective(self: *Self, bitMode: CPU.BitModes) anyerror!void {
            try self.generator.processSetBitModeDirective(bitMode);
        }

        pub fn processSetOriginDirective(self: *Self, origin: usize) anyerror!void {
            try self.generator.processSetOriginDirective(origin);
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
    };
}
