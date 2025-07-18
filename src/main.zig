const std = @import("std");
const sdl = @import("sdl3");
const Program = @import("program.zig");
const Stack = @import("stack/internal.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};

pub const main_bg = sdl.pixels.Color{ .r = 160, .g = 160, .b = 160, .a = 255 };
var global_program: *Program = undefined;
fn add(a: i32, b: i32) i32 {
    return global_program.stack.call(add2, .{ a, b }, "add2");
}

fn add2(a: i32, b: i32) i32 {
    return global_program.stack.call(add3, .{ a, b }, "add3");
}

fn add3(a: i32, b: i32) i32 {
    return a + b;
}
const threeNums = struct {
    num1: i32 = 1,
    num2: i32 = 2,
    num3: i32 = 3,
    num4: i128 = 4,
    num5: i32 = 5475545,
};

pub fn main() !void {
    var program = try Program.init(gpa.allocator());
    global_program = program;

    var list = std.SinglyLinkedList(i32){ .first = program.heap.create(std.SinglyLinkedList(i32).Node{ .data = 32 }, gpa.allocator()) };
    var timer = std.time.Timer.start() catch unreachable;
    for (0..30) |idx| {
        list.prepend(program.heap.create(std.SinglyLinkedList(i32).Node{ .data = @intCast(idx) }, gpa.allocator()));
        program.heap.update(list.first.?);
    }

    std.debug.print("total: {d}\n", .{timer.read()});
    while (list.popFirst()) |first| {
        program.heap.destroy(first, gpa.allocator());
    }

    program.start();
    program.deinit();
    const leak = gpa.detectLeaks();
    std.debug.print("leak: {}\n", .{leak});
}
