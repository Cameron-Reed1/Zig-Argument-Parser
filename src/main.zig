const std = @import("std");
const arguments = @import("root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var first = arguments.IntArgument.init(&[_][]const u8{"first"}, &[_]u8{'f'}, 0);
    var second = arguments.StringArgument.init(&[_][]const u8{"second"}, &[_]u8{'s'}, "");
    var third = arguments.BoolArgument.init(&[_][]const u8{"third"}, &[_]u8{'t'});
    var fourth = arguments.BoolArgument.init(&[_][]const u8{"fourth"}, &[_]u8{'x'});

    var name = arguments.PositionalStringArgument.init("", true);
    var age = arguments.PositionalIntArgument.init(0, true);
    var optional = arguments.PositionalStringArgument.init("", false);

    var args = [_]*arguments.Argument{ &first.arg, &second.arg, &third.arg, &fourth.arg };
    var posArgs = [_]*arguments.PositionalArgument{ &name.arg, &age.arg, &optional.arg };
    arguments.parse(allocator, &args, &posArgs) catch return;

    if (first.found) {
        std.debug.print("First: {}\n", .{first.value});
    } else {
        std.debug.print("First:\n", .{});
    }
    std.debug.print("Second: {s}\n", .{if (second.found) second.value else "N/A"});
    std.debug.print("Third: {}\n", .{third.found});
    std.debug.print("Fourth: {}\n\n", .{fourth.found});

    std.debug.print("Name: {s}\n", .{name.value});
    std.debug.print("Age: {}\n", .{age.value});
    std.debug.print("Optional: {s}\n", .{optional.value});
}
