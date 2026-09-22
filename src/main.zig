const std = @import("std");
const process = std.process;
const mem = std.mem;
const heap = std.heap;
const fmt = std.fmt;
const enums = std.enums;
const os = std.os;
const Io = std.Io;

const interpereter_name: []const u8 = "iii";
const version: []const u8 = "0.0.1";
const max_file_size = 10 * 1024 * 1024; // 10MB

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
    var memory_size: usize = 4096; // 4kb
    var trace = false;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    while (args.next()) |arg| {
        const flag = Flag.parse(arg) orelse {
            if (path != null) {
                try stderr.print("error: unexpected argument '{s}' (file '{s}' already provided)\n", .{ arg, path.? });
                process.exit(1);
            }
            path = arg;
            continue;
        };

        switch (flag) {
            .Help => {
                try stderr.writeAll("Usage:\n");
                try stderr.print("\t{s} <file>\trun script from file\n", .{interpereter_name});
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
            .Symbols => {
                try stderr.writeAll("Code Symbols:\n");
                for (enums.values(Instruction)) |instruction| {
                    switch (instruction) {
                        .Halt => {
                            try stderr.print("\tnull ({d})\t{s}\n", .{ instruction.symbol(), instruction.description() });
                        },
                        .Number_0, .Number_1, .Number_2, .Number_3, .Number_4, .Number_5, .Number_6, .Number_7, .Number_8 => {},
                        .Number_9 => {
                            try stderr.print("\t0-9\t\t{s}\n", .{instruction.description()});
                        },
                        .BitAnd => {
                            try stderr.print("\n\tbitwise operations (left side: memory value, right side: accumulator):\n\t{c}\t\t{s}\n", .{ instruction.symbol(), instruction.description() });
                        },
                        .BitShiftRight => {
                            try stderr.print("\t{c}\t\t{s}\n\n", .{ instruction.symbol(), instruction.description() });
                        },

                        else => {
                            try stderr.print("\t{c}\t\t{s}\n", .{ instruction.symbol(), instruction.description() });
                        },
                    }
                }
                process.exit(0);
            },
            .Version => {
                try stderr.print("{s} v{s}\n", .{ interpereter_name, version });
                process.exit(0);
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
            .CodeExecution => {
                code = args.next() orelse {
                    try stderr.print("error: expected <{s}> after {s}\n", .{ Flag.metavar(.CodeExecution).?, Flag.short(.CodeExecution) });
                    process.exit(1);
                };
            },
            .TraceMode => {
                trace = true;
            },
        }
    }

    var src: []const u8 = undefined;

    if (code == null and path == null) {
        try stderr.print("error: no input, use {s} for help\n", .{Flag.short(.Help)});
        process.exit(1);
    } else if (code != null and path != null) {
        try stderr.writeAll("error: only one input can be used\n");
        process.exit(1);
    } else if (code) |code_str| {
        src = code_str;
    } else if (path) |path_str| {
        src = try Io.Dir.cwd().readFileAlloc(io, path_str, allocator, @enumFromInt(max_file_size));
    }

    const instructions = if (trace)
        try buildInstructionArray(allocator, true, src)
    else
        try buildInstructionArray(allocator, false, src);

    defer allocator.free(instructions);

    var interpereter: Interpereter = try .init(allocator, memory_size, instructions);
    defer interpereter.deinit();

    const exit_code = try interpereter.run(stderr);

    defer process.exit(exit_code);
}

fn buildInstructionArray(allocator: mem.Allocator, comptime trace_enabled: bool, src: []const u8) ![]Instruction {
    var instructions: std.ArrayList(Instruction) = .empty;
    errdefer instructions.deinit(allocator);

    try instructions.ensureTotalCapacity(allocator, src.len + 1);

    for (src) |char| {
        instructions.appendAssumeCapacity(switch (char) {
            Instruction.symbol(.Exit) => .Exit,
            Instruction.symbol(.Halt) => .Halt,
            Instruction.symbol(.Trace) => if (trace_enabled) .Trace else continue,
            Instruction.symbol(.Number_0) => .Number_0,
            Instruction.symbol(.Number_1) => .Number_1,
            Instruction.symbol(.Number_2) => .Number_2,
            Instruction.symbol(.Number_3) => .Number_3,
            Instruction.symbol(.Number_4) => .Number_4,
            Instruction.symbol(.Number_5) => .Number_5,
            Instruction.symbol(.Number_6) => .Number_6,
            Instruction.symbol(.Number_7) => .Number_7,
            Instruction.symbol(.Number_8) => .Number_8,
            Instruction.symbol(.Number_9) => .Number_9,
            Instruction.symbol(.AccumulatorZero) => .AccumulatorZero,
            Instruction.symbol(.AccumulatorSet) => .AccumulatorSet,
            Instruction.symbol(.LoopStart) => .LoopStart,
            Instruction.symbol(.LoopEnd) => .LoopEnd,
            Instruction.symbol(.PointerGoto) => .PointerGoto,
            Instruction.symbol(.PointerLeft) => .PointerLeft,
            Instruction.symbol(.PointerRight) => .PointerRight,
            Instruction.symbol(.MemoryAssign) => .MemoryAssign,
            Instruction.symbol(.MemoryIncrement) => .MemoryIncrement,
            Instruction.symbol(.MemoryDecrement) => .MemoryDecrement,
            Instruction.symbol(.BitAnd) => .BitAnd,
            Instruction.symbol(.BitOr) => .BitOr,
            Instruction.symbol(.BitXor) => .BitXor,
            Instruction.symbol(.BitShiftLeft) => .BitShiftLeft,
            Instruction.symbol(.BitShiftRight) => .BitShiftRight,
            Instruction.symbol(.Write) => .Write,
            Instruction.symbol(.Read) => .Read,
            Instruction.symbol(.SetPipe) => .SetPipe,
            else => continue,
        });
    }

    instructions.appendAssumeCapacity(.Halt);

    return try instructions.toOwnedSlice(allocator);
}

const Flag = enum {
    Help,
    Symbols,
    Version,
    MemorySize,
    CodeExecution,
    TraceMode,

    const Self = @This();

    pub fn short(self: Self) []const u8 {
        return switch (self) {
            .Help => "-h",
            .Symbols => "-s",
            .Version => "-v",
            .MemorySize => "-m",
            .CodeExecution => "-c",
            .TraceMode => "-t",
        };
    }

    pub fn metavar(self: Self) ?[]const u8 {
        return switch (self) {
            .MemorySize => "size",
            .CodeExecution => "code",
            else => null,
        };
    }

    pub fn description(self: Self) []const u8 {
        return switch (self) {
            .Help => "prints the usage of the interpereter",
            .Symbols => "prints the code symbols of the interpereter",
            .Version => "prints the version of the interpereter",
            .MemorySize => "sets the memory size (must be a power of 2)",
            .CodeExecution => "executes the given code",
            .TraceMode => "allows the interpereter to allow the trace symbol to be used in scripts",
        };
    }

    pub fn parse(str: []const u8) ?Self {
        for (enums.values(Self)) |flag| {
            if (mem.eql(u8, str, flag.short())) return flag;
        }
        return null;
    }
};

pub const Instruction = enum {
    Exit,
    Halt,

    Trace,

    Number_0,
    Number_1,
    Number_2,
    Number_3,
    Number_4,
    Number_5,
    Number_6,
    Number_7,
    Number_8,
    Number_9,

    AccumulatorZero,
    AccumulatorSet,

    LoopStart,
    LoopEnd,

    PointerGoto,
    PointerRight,
    PointerLeft,

    MemoryAssign,
    MemoryIncrement,
    MemoryDecrement,

    BitAnd,
    BitOr,
    BitXor,
    BitShiftLeft,
    BitShiftRight,

    Write,
    Read,
    SetPipe,

    const Self = @This();

    pub fn symbol(self: Self) u8 {
        return switch (self) {
            .Exit => '!',
            .Halt => 0,
            .Trace => '?',
            .Number_0 => '0',
            .Number_1 => '1',
            .Number_2 => '2',
            .Number_3 => '3',
            .Number_4 => '4',
            .Number_5 => '5',
            .Number_6 => '6',
            .Number_7 => '7',
            .Number_8 => '8',
            .Number_9 => '9',
            .AccumulatorZero => '_',
            .AccumulatorSet => '$',
            .LoopStart => '[',
            .LoopEnd => ']',
            .PointerGoto => '@',
            .PointerLeft => '<',
            .PointerRight => '>',
            .MemoryAssign => '=',
            .MemoryIncrement => '+',
            .MemoryDecrement => '-',
            .BitAnd => '&',
            .BitOr => '|',
            .BitXor => '^',
            .BitShiftLeft => '\\',
            .BitShiftRight => '/',
            .Write => '.',
            .Read => ',',
            .SetPipe => ':',
        };
    }

    pub fn description(self: Self) []const u8 {
        return switch (self) {
            .Exit => "exits the program with an exit code from the accumulator",
            .Halt => "stops the program with an automatic exit code of 0 (automatically placed at the end of code)",
            .Trace => "prints the current state of the interpereter into stderr (only works with the trace flag on)",
            .Number_0,
            .Number_1,
            .Number_2,
            .Number_3,
            .Number_4,
            .Number_5,
            .Number_6,
            .Number_7,
            .Number_8,
            .Number_9,
            => "appends the number to the accumulator",
            .AccumulatorZero => "sets the accumulator to 0",
            .AccumulatorSet => "sets the accumulator to the value in memory",
            .LoopStart => "creates a loop that gets jumped to in the code",
            .LoopEnd => "jumps to the start of the loop in the code while the memory value is not 0",
            .PointerGoto => "sets the memory pointer position to the accumulator value",
            .PointerLeft => "moves the memory pointer position to the left by 1",
            .PointerRight => "moves the memory pointer position to the right by 1",
            .MemoryAssign => "sets the current memory value to the accumulator value (max 255)",
            .MemoryIncrement => "increments memory by the accumulator value",
            .MemoryDecrement => "decrements memory by the accumulator value",
            .BitAnd => "bitwise and",
            .BitOr => "bitwise or",
            .BitXor => "bitwise xor",
            .BitShiftLeft => "bit shift left",
            .BitShiftRight => "bit shift right",
            .Write => "writes a memory range to the set pipe (memory pointer is the position, and the accumulator is the size)",
            .Read => "reads data from a set pipe into a range of memory (memory pointer is the position, and the accumulator is the size)",
            .SetPipe => "sets the pipe to the accumulator value",
        };
    }
};

pub const Interpereter = struct {
    allocator: mem.Allocator,
    instructions: []Instruction,
    memory: []u8,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, memory_size: usize, instructions: []Instruction) !Self {
        const memory = try allocator.alloc(u8, memory_size);
        @memset(memory, 0);

        var self: Self = .{
            .allocator = allocator,
            .instructions = instructions,
            .memory = memory,
        };

        try self.parse();

        return self;
    }

    fn parse(self: *Self) !void {
        _ = self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.memory);
    }

    pub fn run(self: *Self, writer: *Io.Writer) !u8 {
        const memory = self.memory;
        const instructions = self.instructions;
        var mem_ptr: usize = 0;
        var inst_ptr: usize = 0;
        var accumulator: usize = 0;
        var jump_pos: usize = 0;
        var pipe_fd: i32 = 0;

        dispatch: switch (instructions[inst_ptr]) {
            .Exit => return @truncate(accumulator),
            .Halt => return 0,
            .Trace => {
                try writer.print(
                    "i: {d:<4} | mem {d:<6}: {d} ({c}) | acc: {d:<6} | pipe: {d:<4}\n",
                    .{ inst_ptr, mem_ptr, memory[mem_ptr], memory[mem_ptr], accumulator, pipe_fd },
                );
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Number_0 => {
                accumulator = (accumulator *% 10) +% 0;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Number_1 => {
                accumulator = (accumulator *% 10) +% 1;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Number_2 => {
                accumulator = (accumulator *% 10) +% 2;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Number_3 => {
                accumulator = (accumulator *% 10) +% 3;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Number_4 => {
                accumulator = (accumulator *% 10) +% 4;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Number_5 => {
                accumulator = (accumulator *% 10) +% 5;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Number_6 => {
                accumulator = (accumulator *% 10) +% 6;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Number_7 => {
                accumulator = (accumulator *% 10) +% 7;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Number_8 => {
                accumulator = (accumulator *% 10) +% 8;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Number_9 => {
                accumulator = (accumulator *% 10) +% 9;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .AccumulatorZero => {
                accumulator = 0;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .AccumulatorSet => {
                accumulator = memory[mem_ptr];
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .LoopStart => {
                jump_pos = inst_ptr;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .LoopEnd => {
                inst_ptr = if (memory[mem_ptr] != 0) jump_pos else inst_ptr;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .PointerGoto => {
                mem_ptr = accumulator % memory.len;
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .PointerLeft => {
                mem_ptr = (mem_ptr -% 1) & (memory.len - 1);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .PointerRight => {
                mem_ptr = (mem_ptr + 1) & (memory.len - 1);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .MemoryAssign => {
                memory[mem_ptr] = @truncate(accumulator);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .MemoryIncrement => {
                memory[mem_ptr] +%= @truncate(accumulator);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .MemoryDecrement => {
                memory[mem_ptr] -%= @truncate(accumulator);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .BitAnd => {
                memory[mem_ptr] &= @truncate(accumulator);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .BitOr => {
                memory[mem_ptr] |= @truncate(accumulator);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .BitXor => {
                memory[mem_ptr] ^= @truncate(accumulator);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .BitShiftLeft => {
                memory[mem_ptr] <<= @truncate(accumulator);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .BitShiftRight => {
                memory[mem_ptr] >>= @truncate(accumulator);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Write => {
                accumulator = try pipeWrite(pipe_fd, memory[mem_ptr .. mem_ptr + accumulator]);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .Read => {
                accumulator = try pipeRead(pipe_fd, memory[mem_ptr .. mem_ptr + accumulator]);
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
            .SetPipe => {
                pipe_fd = @bitCast(@as(u32, @truncate(accumulator)));
                inst_ptr += 1;
                continue :dispatch instructions[inst_ptr];
            },
        }

        return 0;
    }

    fn pipeWrite(fd: i32, buf: []u8) !usize {
        while (true) {
            const rc = os.linux.write(fd, buf.ptr, buf.len);
            switch (os.linux.errno(rc)) {
                .SUCCESS => return rc,
                .INTR => continue,
                else => return error.WriteFailed,
            }
        }
    }

    fn pipeRead(fd: i32, buf: []u8) !usize {
        while (true) {
            const rc = os.linux.read(fd, buf.ptr, buf.len);
            switch (os.linux.errno(rc)) {
                .SUCCESS => return rc,
                .INTR => continue,
                else => return error.ReadFailed,
            }
        }
    }
};
