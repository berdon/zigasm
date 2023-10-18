const std = @import("std");

pub fn allocBytesFromNumber(comptime SizeType: type, sizeInBytes: u8, value: SizeType, allocator: std.mem.Allocator) anyerror![]const u8 {
    var buffer = try allocator.alloc(u8, sizeInBytes);
    for (0..buffer.len) |i| buffer[i] = 0;
    var temp: SizeType = @intCast(value);
    for (0..buffer.len) |i| {
        buffer[i] = @intCast(0xFF & temp);
        temp = temp >> 8;
    }
    return buffer;
}

test "allocBytesFromNumber returns expected 1/" {
    var allocator = std.testing.allocator;
    var result = try allocBytesFromNumber(2, 0x1337, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x37, 0x13 }, result);
}

test "allocBytesFromNumber returns expected 2/" {
    var allocator = std.testing.allocator;
    var result = try allocBytesFromNumber(4, 0x1337, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x37, 0x13, 0x0, 0x0 }, result);
}
