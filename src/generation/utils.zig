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

pub fn allocBytesFromNumberWithDefault(comptime SizeType: type, sizeInBytes: u8, value: SizeType, default: u8, allocator: std.mem.Allocator) anyerror![]const u8 {
    var buffer = try allocator.alloc(u8, sizeInBytes);
    for (0..buffer.len) |i| buffer[i] = default;
    var temp: SizeType = @intCast(value);
    for (0..buffer.len) |i| {
        buffer[i] = @intCast(0xFF & temp);
        temp = temp >> 8;
    }
    return buffer;
}

test "allocBytesFromNumber returns expected 1/" {
    var allocator = std.testing.allocator;
    var result = try allocBytesFromNumber(isize, 2, 0x1337, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x37, 0x13 }, result);
}

test "allocBytesFromNumber returns expected 2/" {
    var allocator = std.testing.allocator;
    var result = try allocBytesFromNumber(isize, 4, 0x1337, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x37, 0x13, 0x0, 0x0 }, result);
}

pub fn requiredBytesForSignedInteger(value: isize) u8 {
    var bytes: u8 = 1;
    while (value < -std.math.pow(isize, 2, (bytes * 7)) or value >= std.math.pow(isize, 2, (bytes * 7))) {
        bytes += 1;
    }
    return bytes;
}

test "requiredBytesForSignedInteger returns expected" {
    try std.testing.expectEqual(@as(u8, 1), requiredBytesForSignedInteger(-128));
    try std.testing.expectEqual(@as(u8, 2), requiredBytesForSignedInteger(-129));
    try std.testing.expectEqual(@as(u8, 1), requiredBytesForSignedInteger(127));
    try std.testing.expectEqual(@as(u8, 2), requiredBytesForSignedInteger(128));
}

pub fn requiredBytesForUnsignedInteger(value: usize) u8 {
    var bytes: u8 = 1;
    while (value >= std.math.pow(usize, 2, (bytes * 8))) {
        bytes += 1;
    }
    return bytes;
}

test "requiredBytesForUnsignedInteger returns expected" {
    try std.testing.expectEqual(@as(u8, 1), requiredBytesForUnsignedInteger(255));
    try std.testing.expectEqual(@as(u8, 2), requiredBytesForUnsignedInteger(256));
    try std.testing.expectEqual(@as(u8, 2), requiredBytesForUnsignedInteger(65535));
    try std.testing.expectEqual(@as(u8, 3), requiredBytesForUnsignedInteger(65536));
}
