const std = @import("std");
const sdl = @import("sdl3");
const Program = @import("program.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){}; // allocator
var GP: *Program = undefined; // program instance for global use
var GC: []i32 = undefined; //cache for fib

fn cachedFib(num: i32) i32 {
    const cache = GP.heap.alloc(i32, @intCast(num + 1), gpa.allocator());
    defer GP.heap.destroy(cache, gpa.allocator());
    for (cache) |*item| {
        item.* = -1;
        GP.heap.update(cache);
    }
    GC = cache;
    return GP.stack.call(fibWithCache, .{num}, "Fib");
}

fn fibWithCache(num: i32) i32 {
    const num_usize: usize = @intCast(num);
    if (GC[num_usize] != -1) {
        return GC[num_usize];
    }
    if (num <= 1) {
        GC[num_usize] = num;
        GP.heap.update(GC);
        return num;
    }
    GC[num_usize] = GP.stack.call(fibWithCache, .{num - 1}, "Fib") + GP.stack.call(fibWithCache, .{num - 2}, "Fib");
    GP.heap.update(GC);
    return GC[num_usize];
}

fn fib(num: i32) i32 {
    if (num <= 1) return num;
    return GP.stack.call(fib, .{num - 1}, "fib") + GP.stack.call(fib, .{num - 2}, "fib");
}

pub fn main() !void {
    var program = try Program.init(gpa.allocator());
    GP = program;
    _ = program.stack.call(fib, .{5}, "fib");

    program.start();
    program.deinit();
    const leak = gpa.detectLeaks();
    std.debug.print("leak: {}\n", .{leak});
}
