///Simplyfies the use of time blocks in regards to units and numeric types.
const std = @import("std");
const time_type = f64;
const Self = @This();

time: time_type,
unit: TimeUnit,

pub fn init(time: anytype, unit: TimeUnit) timeError!Self {
    const result: time_type = switch (@typeInfo(@TypeOf(time))) {
        .float, .comptime_float => @floatCast(time),
        .int, .comptime_int => @floatFromInt(time),
        else => @compileError("can't convert time to non numeric"),
    };

    return if (result < 0) timeError.lessThanZero else Self{ .time = result, .unit = unit };
}

///compares self with other.
/// if self > other, return 1
/// if self < other, return -1
/// if self == other, return 0
pub fn compareTo(self: Self, other: Self) i8 {
    const other_time = other.inUnit(self.unit).time;
    const result: i8 = if (self.time > other_time) 1 else if (self.time < other_time) -1 else 0;
    return result;
}

pub fn multiply(self: Self, scalar: time_type) timeError!Self {
    const result = self.time * scalar;
    return if (result < 0) timeError.lessThanZero else Self{ .time = result, .unit = self.unit };
}

///get time as a numeric at a unit of choice.
pub fn getAs(self: Self, Type: type, unit: TimeUnit) Type {
    const time_in_correct_unit = self.inUnit(unit);
    const result: Type = switch (@typeInfo(Type)) {
        .float => @floatCast(time_in_correct_unit.time),
        .int => @intFromFloat(time_in_correct_unit.time),
        else => @compileError("can't convert time to non numeric or comptime"),
    };
    return result;
}

/// convert time to a different unit
pub fn inUnit(time: Self, to: TimeUnit) Self {
    var result: time_type = time.time;
    result *= std.math.pow(time_type, 1000, @floatFromInt(@intFromEnum(to) - @intFromEnum(time.unit)));
    return Self{ .time = result, .unit = to };
}

/// return time left after time in parameter passed
/// if other is greater or equal to self,
/// function will return zero.
pub fn subtract(self: Self, other: Self) Self {
    const time_in_correct_unit = other.inUnit(self.unit);
    var result: time_type = self.time - time_in_correct_unit.time;
    if (result < 0) result = 0; // time cant be negative.
    return Self{ .time = result, .unit = self.unit };
}

pub fn add(self: Self, other: Self) Self {
    const time_in_correct_unit = other.inUnit(self.unit);
    const result: time_type = self.time + time_in_correct_unit.time;
    return Self{ .time = result, .unit = self.unit };
}

pub const TimeUnit = enum(i8) {
    Seconds = 0,
    Milliseconds = 1,
    Microseconds = 2,
    Nanoseconds = 3,
};

const timeError = error{
    lessThanZero,
};

test "Time Unit Conversion" {
    const time = Self.init(1, .Seconds) catch unreachable;
    const converted_time = time.inUnit(.Milliseconds);
    try std.testing.expectEqual(converted_time.time, 1000.0);
}

test "Time Addition" {
    const time1 = Self.init(1.0, .Seconds) catch unreachable;
    const time2 = Self.init(2.0, .Milliseconds) catch unreachable;
    const added_time = time1.add(time2);
    try std.testing.expectEqual(added_time.getAs(f64, .Milliseconds), 1002.0);
}

test "Time Subtraction" {
    const time1 = Self.init(1.0, .Seconds) catch unreachable;
    const time2 = Self.init(2.0, .Milliseconds) catch unreachable;
    const subtracted_time = time1.subtract(time2);
    try std.testing.expectEqual(subtracted_time.getAs(f64, .Milliseconds), 998.0);
}

test "comparison" {
    const time1 = Self.init(1.0, .Seconds) catch unreachable;
    const time2 = Self.init(2.0, .Milliseconds) catch unreachable;
    try std.testing.expectEqual(time1.compareTo(time2), 1);
}

test "init error" {
    try std.testing.expectError(error.lessThanZero, Self.init(-1.0, .Seconds));
    try std.testing.expectError(error.lessThanZero, Self.init(-0.1, .Microseconds));
}
