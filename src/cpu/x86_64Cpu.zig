const std = @import("std");
const cpu = @import("cpu.zig");

const SupportChecker = *const fn (name: []const u8) void;
pub const Register = struct {
    const Self = @This();

    name: []const u8,
    register: x86_64Registers,
    registerIndex: ?u16,
    size: cpu.BitSizes,
    supports16bit: bool,
    supports32bit: bool,
    supports64bit: bool,
    supportsChecker: ?SupportChecker,
    requiredExtensions: ?[]const Extensions,

    pub fn supportedByBitMode(self: Self, bitMode: cpu.BitModes) bool {
        return switch (bitMode) {
            .Bit16 => self.supports16bit,
            .Bit32 => self.supports32bit,
            .Bit64 => self.supports64bit,
        };
    }
};
fn register(name: []const u8, regEnum: x86_64Registers, registerIndex: ?u16, size: cpu.BitSizes, supports16bit: bool, supports32bit: bool, supports64bit: bool, supportChecker: ?SupportChecker, requiredExtensions: ?[]const Extensions) Register {
    return .{
        .name = name,
        .size = size,
        .register = regEnum,
        .registerIndex = registerIndex,
        .supports16bit = supports16bit,
        .supports32bit = supports32bit,
        .supports64bit = supports64bit,
        .supportsChecker = supportChecker,
        .requiredExtensions = requiredExtensions,
    };
}
pub const Extensions = enum {
    REX,
    REX_W,
    APX,
};
const RegisterStringMapType = std.StringHashMap(Register);
const RegisterEnumMapType = std.AutoHashMap(x86_64Registers, Register);
pub const x86_64CpuContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator = undefined,
    registerStringMap: RegisterStringMapType,
    registerEnumMap: RegisterEnumMapType,

    pub fn init(allocator: std.mem.Allocator) anyerror!Self {
        var result = Self{
            .allocator = allocator,
            .registerStringMap = undefined,
            .registerEnumMap = undefined,
        };
        try initializeRegisters(&result, allocator);
        return result;
    }

    pub fn deinit(self: *Self) void {
        self.registerStringMap.deinit();
        self.registerEnumMap.deinit();
    }

    fn initializeRegisters(result: *x86_64CpuContext, allocator: std.mem.Allocator) anyerror!void {
        result.registerStringMap = RegisterStringMapType.init(allocator);
        try result.registerStringMap.put("al", register("al", .al, 0, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("cl", register("cl", .cl, 1, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("dl", register("dl", .dl, 2, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("bl", register("bl", .bl, 3, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("ah", register("ah", .ah, 4, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("ch", register("ch", .ch, 5, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("dh", register("dh", .dh, 6, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("bh", register("bh", .bh, 7, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("sil", register("sil", .sil, null, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("dil", register("dil", .dil, null, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("bpl", register("bpl", .bpl, null, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("spl", register("spl", .spl, null, .Bits8, true, true, true, null, null));
        try result.registerStringMap.put("r8b", register("r8b", .r8b, null, .Bits8, false, false, true, null, null));
        try result.registerStringMap.put("r9b", register("r9b", .r9b, null, .Bits8, false, false, true, null, null));
        try result.registerStringMap.put("r10b", register("r10b", .r10b, null, .Bits8, false, false, true, null, null));
        try result.registerStringMap.put("r11b", register("r11b", .r11b, null, .Bits8, false, false, true, null, null));
        try result.registerStringMap.put("r12b", register("r12b", .r12b, null, .Bits8, false, false, true, null, null));
        try result.registerStringMap.put("r13b", register("r13b", .r13b, null, .Bits8, false, false, true, null, null));
        try result.registerStringMap.put("r14b", register("r14b", .r14b, null, .Bits8, false, false, true, null, null));
        try result.registerStringMap.put("r15b", register("r15b", .r15b, null, .Bits8, false, false, true, null, null));
        try result.registerStringMap.put("r16b", register("r16b", .r16b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r17b", register("r17b", .r17b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r18b", register("r18b", .r18b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r19b", register("r19b", .r19b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r20b", register("r20b", .r20b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r21b", register("r21b", .r21b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r22b", register("r22b", .r22b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r23b", register("r23b", .r23b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r24b", register("r24b", .r24b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r25b", register("r25b", .r25b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r26b", register("r26b", .r26b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r27b", register("r27b", .r27b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r28b", register("r28b", .r28b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r29b", register("r29b", .r29b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r30b", register("r30b", .r30b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r31b", register("r31b", .r31b, null, .Bits8, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("ax", register("ax", .ax, 0, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("cx", register("cx", .cx, 1, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("dx", register("dx", .dx, 2, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("bx", register("bx", .bx, 3, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("r8w", register("r8w", .r8w, null, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("r9w", register("r9w", .r9w, null, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("r10w", register("r10w", .r10w, null, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("r11w", register("r11w", .r11w, null, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("r12w", register("r12w", .r12w, null, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("r13w", register("r13w", .r13w, null, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("r14w", register("r14w", .r14w, null, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("r15w", register("r15w", .r15w, null, .Bits16, true, true, true, null, null));
        try result.registerStringMap.put("r16w", register("r16w", .r16w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r17w", register("r17w", .r17w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r18w", register("r18w", .r18w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r19w", register("r19w", .r19w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r20w", register("r20w", .r20w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r21w", register("r21w", .r21w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r22w", register("r22w", .r22w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r23w", register("r23w", .r23w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r24w", register("r24w", .r24w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r25w", register("r25w", .r25w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r26w", register("r26w", .r26w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r27w", register("r27w", .r27w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r28w", register("r28w", .r28w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r29w", register("r29w", .r29w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r30w", register("r30w", .r30w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r31w", register("r31w", .r31w, null, .Bits16, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("eax", register("eax", .eax, 0, .Bits32, true, true, true, null, null));
        try result.registerStringMap.put("ecx", register("ecx", .ecx, 1, .Bits32, true, true, true, null, null));
        try result.registerStringMap.put("edx", register("edx", .edx, 2, .Bits32, true, true, true, null, null));
        try result.registerStringMap.put("ebx", register("ebx", .ebx, 3, .Bits32, true, true, true, null, null));
        try result.registerStringMap.put("esi", register("esi", .esi, null, .Bits32, true, true, true, null, null));
        try result.registerStringMap.put("edi", register("edi", .edi, null, .Bits32, true, true, true, null, null));
        try result.registerStringMap.put("ebp", register("ebp", .ebp, null, .Bits32, true, true, true, null, null));
        try result.registerStringMap.put("esp", register("esp", .esp, null, .Bits32, true, true, true, null, null));
        try result.registerStringMap.put("r8d", register("r8d", .r8d, null, .Bits32, false, false, true, null, null));
        try result.registerStringMap.put("r9d", register("r9d", .r9d, null, .Bits32, false, false, true, null, null));
        try result.registerStringMap.put("r10d", register("r10d", .r10d, null, .Bits32, false, false, true, null, null));
        try result.registerStringMap.put("r11d", register("r11d", .r11d, null, .Bits32, false, false, true, null, null));
        try result.registerStringMap.put("r12d", register("r12d", .r12d, null, .Bits32, false, false, true, null, null));
        try result.registerStringMap.put("r13d", register("r13d", .r13d, null, .Bits32, false, false, true, null, null));
        try result.registerStringMap.put("r14d", register("r14d", .r14d, null, .Bits32, false, false, true, null, null));
        try result.registerStringMap.put("r15d", register("r15d", .r15d, null, .Bits32, false, false, true, null, null));
        try result.registerStringMap.put("r16d", register("r16d", .r16d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r17d", register("r17d", .r17d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r18d", register("r18d", .r18d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r19d", register("r19d", .r19d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r20d", register("r20d", .r20d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r21d", register("r21d", .r21d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r22d", register("r22d", .r22d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r23d", register("r23d", .r23d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r24d", register("r24d", .r24d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r25d", register("r25d", .r25d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r26d", register("r26d", .r26d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r27d", register("r27d", .r27d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r28d", register("r28d", .r28d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r29d", register("r29d", .r29d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r30d", register("r30d", .r30d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r31d", register("r31d", .r31d, null, .Bits32, true, true, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("rax", register("rax", .rax, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("rcx", register("rcx", .rcx, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("rdx", register("rdx", .rdx, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("rbx", register("rbx", .rbx, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("rsi", register("rsi", .rsi, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("rdi", register("rdi", .rdi, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("rbp", register("rbp", .rbp, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("rsp", register("rsp", .rsp, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("r8", register("r8", .r8, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("r9", register("r9", .r9, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("r10", register("r10", .r10, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("r11", register("r11", .r11, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("r12", register("r12", .r12, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("r13", register("r13", .r13, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("r14", register("r14", .r14, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("r15", register("r15", .r15, null, .Bits64, false, false, true, null, null));
        try result.registerStringMap.put("r16", register("r16", .r16, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r17", register("r17", .r17, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r18", register("r18", .r18, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r19", register("r19", .r19, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r20", register("r20", .r20, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r21", register("r21", .r21, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r22", register("r22", .r22, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r23", register("r23", .r23, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r24", register("r24", .r24, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r25", register("r25", .r25, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r26", register("r26", .r26, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r27", register("r27", .r27, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r28", register("r28", .r28, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r29", register("r29", .r29, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r30", register("r30", .r30, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));
        try result.registerStringMap.put("r31", register("r31", .r31, null, .Bits64, false, false, true, null, &[_]Extensions{.APX}));

        result.registerEnumMap = RegisterEnumMapType.init(allocator);
        var iterator = result.registerStringMap.valueIterator();
        while (iterator.next()) |r| {
            try result.registerEnumMap.put(r.register, r.*);
        }
    }

    pub fn supportsRegisters(self: Self, name: []const u8) bool {
        return self.registerStringMap.contains(name);
    }

    pub fn resolveRegister(self: Self, name: []const u8) ?Register {
        return self.registerStringMap.get(name);
    }
};

pub fn x86_64Cpu() type {
    return cpu.cpu(x86_64CpuContext, Register);
}

pub const x86_64Registers = enum {
    al,
    cl,
    dl,
    bl,
    ah,
    ch,
    dh,
    bh,
    sil,
    dil,
    bpl,
    spl,
    r8b,
    r9b,
    r10b,
    r11b,
    r12b,
    r13b,
    r14b,
    r15b,
    r16b,
    r17b,
    r18b,
    r19b,
    r20b,
    r21b,
    r22b,
    r23b,
    r24b,
    r25b,
    r26b,
    r27b,
    r28b,
    r29b,
    r30b,
    r31b,
    ax,
    cx,
    dx,
    bx,
    si,
    di,
    bp,
    sp,
    r8w,
    r9w,
    r10w,
    r11w,
    r12w,
    r13w,
    r14w,
    r15w,
    r16w,
    r17w,
    r18w,
    r19w,
    r20w,
    r21w,
    r22w,
    r23w,
    r24w,
    r25w,
    r26w,
    r27w,
    r28w,
    r29w,
    r30w,
    r31w,
    eax,
    ebx,
    ecx,
    edx,
    esi,
    edi,
    ebp,
    esp,
    r8d,
    r9d,
    r10d,
    r11d,
    r12d,
    r13d,
    r14d,
    r15d,
    r16d,
    r17d,
    r18d,
    r19d,
    r20d,
    r21d,
    r22d,
    r23d,
    r24d,
    r25d,
    r26d,
    r27d,
    r28d,
    r29d,
    r30d,
    r31d,
    rax,
    rbx,
    rcx,
    rdx,
    rsi,
    rdi,
    rbp,
    rsp,
    r8,
    r9,
    r10,
    r11,
    r12,
    r13,
    r14,
    r15,
    r16,
    r17,
    r18,
    r19,
    r20,
    r21,
    r22,
    r23,
    r24,
    r25,
    r26,
    r27,
    r28,
    r29,
    r30,
    r31,
};
