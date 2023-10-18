const std = @import("std");
const tk = @import("tokenizer/tokenizer.zig");
const lx = @import("lexer/lexer.zig");
const x86_64Cpu = @import("cpu/x86_64Cpu.zig").x86_64Cpu;
const x86_64Generator = @import("generation/x86_64/x86_64Generator.zig").x86_64Generator;

pub fn main() anyerror!void {
    var allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len <= 2) {
        std.log.err("Expected zygasm input output", .{});
        return;
    }

    const inputFile = args[1];
    const outputFile = args[2];

    const CpuType = x86_64Cpu();
    const GeneratorType = x86_64Generator();
    const TokenizerType = tk.tokenizer();
    var cpu = try CpuType.init(allocator);
    var tokenizerError: ?tk.TokenizerError = undefined;
    var tokenizer = try TokenizerType.init(inputFile, allocator, &tokenizerError);
    defer tokenizer.deinit();
    errdefer tokenizer.deinit();

    var lexer = try lx.lexer(
        TokenizerType,
        CpuType,
        GeneratorType,
    ).init(&cpu, &tokenizer, allocator, outputFile);
    defer lexer.deinit();
    errdefer lexer.deinit();

    _ = lexer.parse() catch |e| {
        if (lexer.err) |err| {
            if (err.location) |location| {
                std.log.info("[{}]:{d}:{d} {s}\n\r", .{ err.err, location.line, location.column, err.message });
            } else {
                std.log.info("[{}]:unknown {s}\n\r", .{ err.err, err.message });
            }
        } else {
            std.log.info("Unexpected exception: {}\n\r", .{e});
        }
    };
}
