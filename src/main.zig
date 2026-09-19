const std = @import("std");
const process = std.process;
const mem = std.mem;
const heap = std.heap;
const fmt = std.fmt;
const enums = std.enums;
const Io = std.Io;

const interpereter = @import("interpereter.zig");

const program_name: []const u8 = "iii";
const version: []const u8 = "0.0.1";

const Flag = enum {
    Help,
    Version,
    BufferSize,
    MemorySize,
    FileExecution,
    CodeExecution,
    VerboseMode,
    DebugMode,

    const Self = @This();

    pub fn short(self: Self) []const u8 {
        return switch (self) {
            .Help => "-h",
            .Version => "-V",
            .BufferSize => "-b",
            .MemorySize => "-m",
            .FileExecution => "-f",
            .CodeExecution => "-c",
            .VerboseMode => "-v",
            .DebugMode => "-d",
        };
    }

    pub fn metavar(self: Self) ?[]const u8 {
        return switch (self) {
            .BufferSize => "size",
            .MemorySize => "memory",
            .FileExecution => "file",
            .CodeExecution => "code",
            else => null,
        };
    }

    pub fn description(self: Self) []const u8 {
        return switch (self) {
            .Help => "prints the usage of the program",
            .Version => "prints the version of the program",
            .BufferSize => "sets the io buffer size",
            .MemorySize => "sets the memory size, must be a power of 2",
            .FileExecution => "reads and executes the code from a file",
            .CodeExecution => "executes the given code",
            .VerboseMode => "turns on verbose mode for the program",
            .DebugMode => "turns on debug mode of the program",
        };
    }

    pub fn parse(str: []const u8) ?Self {
        for (enums.values(Self)) |flag| {
            if (mem.eql(u8, str, flag.short())) return flag;
        }
        return null;
    }
};

pub fn main(init: process.Init) !void {
    const io = init.io;
    var gpa = heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    var stderr_impl = Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_impl.interface;

    var path: ?[]const u8 = null;
    var code: ?[]const u8 = null;
    var memory_size: usize = 32768;
    var buffer_size: usize = 4096;
    var verbose = false;
    var debug = false;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    while (args.next()) |arg| {
        const flag = Flag.parse(arg) orelse {
            try stderr.print("error: the flag: \"{s}\" is not not a valid flag, use {s} for help\n", .{ arg, Flag.short(.Help) });
            process.exit(1);
        };

        switch (flag) {
            .Help => {
                try stderr.writeAll("usage:\n");
                for (enums.values(Flag)) |doc_flag| {
                    try stderr.print("\t{s}", .{doc_flag.short()});
                    if (doc_flag.metavar()) |metavar| {
                        try stderr.print(" <{s}>", .{metavar});
                    } else {
                        try stderr.writeByte('\t');
                    }
                    try stderr.print("\t{s}\n", .{doc_flag.description()});
                }
                process.exit(0);
            },
            .Version => {
                try stderr.print("{s} version: {s}\n", .{ program_name, version });
                process.exit(0);
            },
            .BufferSize => {
                const buffer_size_string = args.next() orelse {
                    try stderr.print("error: expected <{s}> after {s}\n", .{ Flag.metavar(.BufferSize).?, Flag.short(.BufferSize) });
                    process.exit(1);
                };
                buffer_size = try fmt.parseInt(usize, buffer_size_string, 10);
            },
            .MemorySize => {
                const memory_size_string = args.next() orelse {
                    try stderr.print("error: expected <{s}> after {s}\n", .{ Flag.metavar(.MemorySize).?, Flag.short(.MemorySize) });
                    process.exit(1);
                };
                const size = try fmt.parseInt(usize, memory_size_string, 10);

                // checks if it is not a power of 2
                if (size > 0 and (size & (size - 1)) != 0) {
                    try stderr.writeAll("error: memory size must be a power of 2\n");
                    process.exit(1);
                }

                memory_size = try fmt.parseInt(usize, memory_size_string, 10);
            },
            .FileExecution => {
                path = args.next() orelse {
                    try stderr.print("error: expected <{s}> after {s}\n", .{ Flag.metavar(.FileExecution).?, Flag.short(.FileExecution) });
                    process.exit(1);
                };
            },
            .CodeExecution => {
                code = args.next() orelse {
                    try stderr.print("error: expected <{s}> after {s}\n", .{ Flag.metavar(.CodeExecution).?, Flag.short(.CodeExecution) });
                    process.exit(1);
                };
            },
            .VerboseMode => {
                verbose = true;
            },
            .DebugMode => {
                debug = true;
            },
        }
    }

    if (code == null and path == null) {
        try stderr.print("error: no input, use {s} for help\n", .{Flag.short(.Help)});
        process.exit(1);
    }

    if (code != null and path != null) {
        try stderr.writeAll("error: only one input can be used\n");
        process.exit(1);
    }

    const instructions = try buildInstructionArray(allocator);
    defer allocator.free(instructions);
}

fn buildInstructionArray(allocator: mem.Allocator) ![]interpereter.Instruction {
    // read instruction pipe and build instructions from there
    const instructions = allocator.alloc(interpereter.Instruction, 1);
    return instructions;
}
