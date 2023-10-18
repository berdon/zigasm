const std = @import("std");
const lexer = @import("../../lexer/lexer.zig");
const tokenizer = @import("../../tokenizer/tokenizer.zig");
const Errors = @import("../x86_64Generator.zig").Errors;
const GeneratorErrors = @import("../x86_64Generator.zig").GeneratorErrors;
const cpu = @import("../../cpu/cpu.zig");
const utils = @import("../utils.zig");

pub fn emitJump(self: anytype, operand: lexer.Operand, location: tokenizer.Location) GeneratorErrors!void {
    if (operand.accessType == .direct and @as(lexer.ValueType, operand.value) == .constant) {
        var valueByteSize = self.getValueSizeFromBitMode();
        var constantByteSize = try self.countBytes(operand.value.constant, location);
        if (constantByteSize > valueByteSize) {
            // TODO: far jump
        }

        var jumpTarget: isize = operand.valueFromConstant(isize) catch {
            return self.createFormattedError(GeneratorErrors.InternalException, "Failed to parse jump target from \"{s}\".", .{operand.value.constant}, location);
        };
        jumpTarget -= @intCast(self.addressOrigin + self.addressCounter + 1 + valueByteSize);
        var valueBuffer = utils.allocBytesFromNumber(isize, valueByteSize, jumpTarget, self.allocator) catch {
            return self.createFormattedError(GeneratorErrors.InternalException, "Failed to allocate space for jump target value buffer.", .{}, location);
        };
        defer self.allocator.free(valueBuffer);

        var result = std.mem.concat(self.allocator, u8, &[_][]const u8{
            &[_]u8{0xEB},
            valueBuffer,
        }) catch {
            return self.createError(Errors.InternalException, "Failed to combine slices.", location);
        };
        defer self.allocator.free(result);

        try self.emitBytes(result);
    }
}
