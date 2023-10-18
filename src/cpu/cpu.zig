const std = @import("std");

pub const RegisterMapType = std.StringHashMap(struct {});
pub const BitSizes = enum(u8) {
    Bits1,
    Bits2,
    Bits4,
    Bits8,
    Bits16,
    Bits32,
    Bits64,
    Bits128,
    Bits256,
};
pub fn bitSizeFromBytes(bytes: anytype) BitSizes {
    return switch (bytes) {
        1 => .Bits8,
        2 => .Bits16,
        4 => .Bits32,
        8 => .Bits64,
        else => unreachable,
    };
}
pub const BitModes = enum { Bit16, Bit32, Bit64 };
pub fn bitModeFromBits(bits: u8) BitModes {
    return switch (bits) {
        16 => .Bit16,
        32 => .Bit32,
        64 => .Bit64,
        else => unreachable,
    };
}
pub const BitSizesIterator = struct {
    const Self = @This();
    current: u8 = 0,

    pub fn next(self: *Self) ?BitSizes {
        if (self.current > 8) {
            return null;
        }
        defer self.current += 1;
        return @enumFromInt(std.math.pow(u8, 2, self.current) - 1);
    }
};
pub fn bitSizes() BitSizesIterator {
    return .{};
}
pub fn cpu(comptime CpuContextType: type, comptime RegisterType: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        cpu: CpuContextType,

        pub fn getRegisterMap(self: Self) RegisterMapType {
            return self.registers;
        }

        pub fn supportsRegister(self: Self, name: []const u8) bool {
            return self.cpu.supportsRegisters(name);
        }

        pub fn resolveRegister(self: Self, name: []const u8) ?RegisterType {
            return self.cpu.resolveRegister(name);
        }

        pub fn init(allocator: std.mem.Allocator) anyerror!Self {
            var result = Self{
                .allocator = allocator,
                .cpu = undefined,
            };
            result.cpu = try CpuContextType.init(allocator);
            return result;
        }

        pub fn deinit(self: *Self) void {
            self.cpu.deinit();
        }
    };
}
