const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const ParseError = error{
    UnknownArgument,
    MissingArgumentValue,
    MissingPositionalArgument,
    BadPositionalArguments,
    InvalidInteger,
};

const Parser = struct {
    current: []const u8 = undefined,
    isLongArg: bool = false,
    isShortArg: bool = false,

    vtable: struct {
        next: *const fn (self: *Parser) bool,
    },

    fn next(self: *Parser) bool {
        return self.vtable.next(self);
    }

    fn parse(self: *Parser, args: []*Argument, posArgs: []*PositionalArgument) !void {
        if (args.len == 0 and posArgs.len == 0) {
            return;
        }

        if (posArgs.len > 1) {
            var i: usize = 0;
            while (i < posArgs.len - 1) {
                if (!posArgs[i].required and posArgs[i + 1].required) {
                    std.debug.print("All required positional arguments must come before optional positional arguments\n", .{});
                    return ParseError.BadPositionalArguments;
                }
                i += 1;
            }
        }

        var posIndex: usize = 0;
        while (self.next()) {
            if (self.isLongArg) {
                const arg = self.current;
                self.findMatch(args, arg[2..]) catch |err| {
                    switch (err) {
                        ParseError.UnknownArgument => std.debug.print("Unknown argument {s}\n", .{arg}),
                        ParseError.MissingArgumentValue => std.debug.print("Missing argument value for {s}\n", .{arg}),
                        ParseError.InvalidInteger => std.debug.print("{s} expects an integer value, got {s} instead\n", .{ arg, self.current }),
                        else => std.debug.print("Unexpected error occurred\n", .{}),
                    }
                    return err;
                };
            } else if (self.isShortArg) {
                // Short argument
                for (1..self.current.len) |i| {
                    const arg = self.current[i];
                    self.findShortMatches(args, arg, i == self.current.len - 1) catch |err| {
                        switch (err) {
                            ParseError.UnknownArgument => std.debug.print("Unknown argument -{c}\n", .{arg}),
                            ParseError.MissingArgumentValue => std.debug.print("Missing argument value for -{c}\n", .{arg}),
                            ParseError.InvalidInteger => std.debug.print("-{c} expects an integer value, got {s} instead\n", .{ arg, self.current }),
                            else => std.debug.print("Unexpected error occurred\n", .{}),
                        }
                        return err;
                    };
                }
            } else {
                // Positional Argument
                if (posIndex >= posArgs.len) {
                    std.debug.print("Unknown argument {s}\n", .{self.current});
                    return ParseError.UnknownArgument;
                }

                posArgs[posIndex].parse(self.current) catch |err| {
                    switch (err) {
                        ParseError.InvalidInteger => std.debug.print("Expected integer positional argument, got {s} instead\n", .{self.current}),
                        else => std.debug.print("Unexpected error occurred\n", .{}),
                    }
                    return err;
                };
                posIndex += 1;
            }
        }

        if (posIndex < posArgs.len and posArgs[posIndex].required) {
            std.debug.print("Missing required positional argument\n", .{});
            return ParseError.MissingPositionalArgument;
        }
    }

    fn findMatch(self: *Parser, args: []*Argument, str: []const u8) !void {
        for (args) |arg| {
            if (arg.matches(str)) {
                try arg.parse(self);
                return;
            }
        }

        return ParseError.UnknownArgument;
    }

    fn findShortMatches(self: *Parser, args: []*Argument, c: u8, last: bool) !void {
        for (args) |arg| {
            if (arg.shortMatches(c)) {
                if (last) {
                    try arg.parse(self);
                } else {
                    try arg.noVal();
                    try arg.parse(self);
                }
                return;
            }
        }

        return ParseError.UnknownArgument;
    }
};

const ArgvParser = struct {
    index: usize,
    parser: Parser,

    fn init() ArgvParser {
        return .{
            .index = 0,
            .parser = .{ .vtable = .{
                .next = ArgvParser.next,
            } },
        };
    }

    fn next(parser: *Parser) bool {
        var self: *ArgvParser = @fieldParentPtr("parser", parser);

        if (self.index + 1 >= std.os.argv.len) {
            return false;
        }

        self.index += 1;
        self.parser.current = std.mem.span(std.os.argv[self.index]);
        self.parser.isLongArg = false;
        self.parser.isShortArg = false;
        if (self.parser.current.len >= 2 and self.parser.current[0] == '-') {
            self.parser.isShortArg = self.parser.current[1] != '-';
            if (self.parser.current.len >= 3) {
                self.parser.isLongArg = self.parser.current[1] == '-';
            }
        }
        return true;
    }
};

const AllocParser = struct {
    parser: Parser,
    current: []const u8,
    args: std.process.ArgIterator,

    fn init(allocator: std.mem.Allocator) !AllocParser {
        var self = AllocParser{
            .args = try std.process.argsWithAllocator(allocator),
            .current = undefined,
            .parser = .{ .vtable = .{
                .next = AllocParser.next,
            } },
        };

        _ = self.args.next();
        return self;
    }

    fn deinit(self: *AllocParser) void {
        self.args.deinit();
    }

    fn next(parser: *Parser) bool {
        var self: *AllocParser = @fieldParentPtr("parser", parser);
        const val = self.args.next();
        if (val == null) {
            return false;
        }

        self.parser.current = val.?;
        self.parser.isLongArg = false;
        self.parser.isShortArg = false;
        if (self.parser.current.len >= 2 and self.parser.current[0] == '-') {
            self.parser.isShortArg = self.parser.current[1] != '-';
            if (self.parser.current.len >= 3) {
                self.parser.isLongArg = self.parser.current[1] == '-';
            }
        }
        return true;
    }
};

pub const Argument = struct {
    names: []const []const u8,
    shortNames: []const u8,

    vtable: struct {
        parse: *const fn (arg: *Argument, parser: *Parser) ParseError!void,
        noVal: *const fn () ParseError!void,
    },

    fn matches(self: *Argument, arg: []const u8) bool {
        for (self.names) |alias| {
            if (std.mem.eql(u8, arg, alias)) {
                return true;
            }
        }

        return false;
    }

    fn shortMatches(self: *Argument, arg: u8) bool {
        for (self.shortNames) |alias| {
            if (arg == alias) {
                return true;
            }
        }

        return false;
    }

    fn parse(self: *Argument, parser: *Parser) ParseError!void {
        try self.vtable.parse(self, parser);
    }

    fn noVal(self: *Argument) ParseError!void {
        return self.vtable.noVal();
    }
};

pub const IntArgument = struct {
    arg: Argument,
    value: isize,
    found: bool,

    pub fn init(names: []const []const u8, shortNames: []const u8, defaultValue: isize) IntArgument {
        return .{
            .found = false,
            .value = defaultValue,
            .arg = .{ .names = names, .shortNames = shortNames, .vtable = .{ .noVal = IntArgument.noVal, .parse = IntArgument.parse } },
        };
    }

    fn parse(arg: *Argument, parser: *Parser) ParseError!void {
        var self: *IntArgument = @fieldParentPtr("arg", arg);

        if (parser.next() and !parser.isLongArg) {
            self.found = true;
            self.value = std.fmt.parseInt(isize, parser.current, 0) catch {
                return ParseError.InvalidInteger;
            };
        } else {
            return ParseError.MissingArgumentValue;
        }
    }

    fn noVal() ParseError!void {
        return ParseError.MissingArgumentValue;
    }
};

pub const StringArgument = struct {
    arg: Argument,
    value: []const u8,
    found: bool,

    pub fn init(names: []const []const u8, shortNames: []const u8, defaultVal: []const u8) StringArgument {
        return .{
            .found = false,
            .value = defaultVal,
            .arg = .{ .names = names, .shortNames = shortNames, .vtable = .{ .noVal = StringArgument.noVal, .parse = StringArgument.parse } },
        };
    }

    fn parse(arg: *Argument, parser: *Parser) ParseError!void {
        var self: *StringArgument = @fieldParentPtr("arg", arg);

        if (parser.next() and !parser.isLongArg and !parser.isShortArg) {
            self.found = true;
            self.value = parser.current;
        } else {
            return ParseError.MissingArgumentValue;
        }
    }

    fn noVal() ParseError!void {
        return ParseError.MissingArgumentValue;
    }
};

pub const BoolArgument = struct {
    arg: Argument,
    found: bool,

    pub fn init(names: []const []const u8, shortNames: []const u8) BoolArgument {
        return .{
            .found = false,
            .arg = .{ .names = names, .shortNames = shortNames, .vtable = .{ .noVal = BoolArgument.noVal, .parse = BoolArgument.parse } },
        };
    }

    fn parse(arg: *Argument, parser: *Parser) ParseError!void {
        _ = parser;

        var self: *BoolArgument = @fieldParentPtr("arg", arg);
        self.found = true;
    }

    fn noVal() ParseError!void {
        return;
    }
};

pub const PositionalArgument = struct {
    required: bool,

    vtable: struct {
        parse: *const fn (arg: *PositionalArgument, value: []const u8) ParseError!void,
    },

    fn parse(self: *PositionalArgument, value: []const u8) ParseError!void {
        try self.vtable.parse(self, value);
    }
};

pub const PositionalIntArgument = struct {
    arg: PositionalArgument,
    value: isize,
    found: bool,

    pub fn init(defaultValue: isize, required: bool) PositionalIntArgument {
        return .{
            .found = false,
            .value = defaultValue,
            .arg = .{ .required = required, .vtable = .{ .parse = PositionalIntArgument.parse } },
        };
    }

    fn parse(arg: *PositionalArgument, value: []const u8) ParseError!void {
        var self: *PositionalIntArgument = @fieldParentPtr("arg", arg);

        self.found = true;
        self.value = std.fmt.parseInt(isize, value, 0) catch {
            return ParseError.InvalidInteger;
        };
    }
};

pub const PositionalStringArgument = struct {
    arg: PositionalArgument,
    value: []const u8,
    found: bool,

    pub fn init(defaultValue: []const u8, required: bool) PositionalStringArgument {
        return .{
            .found = false,
            .value = defaultValue,
            .arg = .{ .required = required, .vtable = .{ .parse = PositionalStringArgument.parse } },
        };
    }

    fn parse(arg: *PositionalArgument, value: []const u8) ParseError!void {
        var self: *PositionalStringArgument = @fieldParentPtr("arg", arg);

        self.found = true;
        self.value = value;
    }
};

pub fn parse(allocator: std.mem.Allocator, args: []*Argument, posArgs: []*PositionalArgument) !void {
    var allocParser: AllocParser = try AllocParser.init(allocator);
    defer allocParser.deinit();

    try allocParser.parser.parse(args, posArgs);
}

pub fn parseArgv(args: []*Argument, posArgs: []*PositionalArgument) !void {
    var argvParser: ArgvParser = ArgvParser.init();

    try argvParser.parser.parse(args, posArgs);
}

test "basic add functionality" {}
