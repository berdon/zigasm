const std = @import("std");
const tk = @import("tokenizer/tokenizer.zig");
const lx = @import("lexer/lexer.zig");

pub fn main() anyerror!void {
    var allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len <= 1) {
        // TODO
        return;
    }

    var tokenizerError: ?tk.TokenizerError = undefined;
    var tokenizer = try tk.tokenizer(args[1], allocator, &tokenizerError);
    var lexer = lx.lexer(&tokenizer, allocator);
    _ = lexer.parse() catch {
        if (lexer.err.?.location) |location| {
            std.log.info("[{}]:{d}:{d} {s}\n\r", .{ lexer.err.?.err, location.line, location.column, lexer.err.?.message });
        } else {
            std.log.info("[{}]:unknown {s}\n\r", .{ lexer.err.?.err, lexer.err.?.message });
        }
    };
    // while (true) {
    //     const token = tokenizer.next(&tokenizerError) catch {
    //         std.log.info("[{}]:{d}:{d} {s}\n\r", .{ tokenizerError.?.err, tokenizerError.?.location.line, tokenizerError.?.location.column, tokenizerError.?.message });
    //         break;
    //     };
    //     std.log.info("[{}] {s}:{d}:{d}\n\r", .{ token.type, token.lexeme, token.location.line, token.location.column });
    //     if (token.type == .EOF) break;
    // }
}
