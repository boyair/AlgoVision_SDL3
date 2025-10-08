const std = @import("std");
const sdl = @import("sdl3");
const Program = @import("program.zig");
var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){};

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

const intNode = struct {
    value: i32,
    next: std.SinglyLinkedList.Node,
};

//dummy main function
fn dummyMain() void {}
pub fn main() !void {
    var program = try Program.init(gpa.allocator());
    //program.callMain();
    global_program = program;
    _ = program.stack.call(add, .{ 5, 6 }, "add");
    const ListType = std.SinglyLinkedList;
    var list: ListType = .{ .first = null };
    list.first = &program.heap.create(intNode{ .value = 34, .next = .{ .next = null } }, gpa.allocator()).next;

    var timer = std.time.Timer.start() catch unreachable;
    for (0..200) |idx| {
        const node = program.heap.create(intNode{ .value = @intCast(idx), .next = .{ .next = null } }, gpa.allocator());
        list.prepend(&node.next);
        program.heap.update(node);
    }

    std.debug.print("total: {d}\n", .{timer.read()});
    while (list.popFirst()) |first| {
        program.heap.destroy(@as(*intNode, @fieldParentPtr("next", first)), gpa.allocator());
    }

    program.start();
    program.deinit();
    const leak = gpa.detectLeaks();
    std.debug.print("leak: {}\n", .{leak});
}
