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
    var memory_size: usize = 32768;
    var buffer_size: usize = 4096;
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
                try stderr.print("\t{s} <file>\n", .{interpereter_name});
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
                        .Number_0 => try stderr.writeAll("\n    State & Memory:\n"),
                        .InstructionJumpAssign => try stderr.writeAll("\n    Pointers & Jumps:\n"),
                        .MemoryIncrement => try stderr.writeAll("\n    Math & Logic (Left: memory, Right: accumulator):\n"),
                        .BufferWrite => try stderr.writeAll("\n    Input / Output:\n"),
                        else => {},
                    }

                    switch (instruction) {
                        .Number_1, .Number_2, .Number_3, .Number_4, .Number_5, .Number_6, .Number_7, .Number_8, .Number_9 => continue,
                        .Number_0 => try stderr.print("\t0-9\t{s}\n", .{instruction.description()}),
                        else => try stderr.print("\t{c}\t{s}\n", .{ instruction.symbol(), instruction.description() }),
                    }
                }
                process.exit(0);
            },
            .Version => {
                try stderr.print("{s} v{s}\n", .{ interpereter_name, version });
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

    const instructions = try buildInstructionArray(allocator, src);
    defer allocator.free(instructions);

    var io_buffer: IOBuffer = try .init(allocator, buffer_size);
    defer io_buffer.deinit(allocator);

    var interpereter: Interpereter = try .init(allocator, memory_size, instructions, io_buffer);
    defer interpereter.deinit(allocator);

    const exit_code = if (trace)
        try interpereter.run(stderr, true)
    else
        try interpereter.run(stderr, false);

    process.exit(exit_code);
}

fn buildInstructionArray(allocator: mem.Allocator, src: []const u8) ![]Instruction {
    var instructions: std.ArrayList(Instruction) = .empty;
    errdefer instructions.deinit(allocator);

    try instructions.ensureTotalCapacity(allocator, src.len);

    for (src) |char| {
        instructions.appendAssumeCapacity(switch (char) {
            Instruction.symbol(.Exit) => .Exit,
            Instruction.symbol(.DebugDump) => .DebugDump,
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
            Instruction.symbol(.InstructionJumpAssign) => .InstructionJumpAssign,
            Instruction.symbol(.InstructionZeroJump) => .InstructionZeroJump,
            Instruction.symbol(.InstructionJump) => .InstructionJump,
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
            Instruction.symbol(.BufferWrite) => .BufferWrite,
            Instruction.symbol(.BufferRead) => .BufferRead,
            Instruction.symbol(.FetchBuffer) => .FetchBuffer,
            Instruction.symbol(.FlushBuffer) => .FlushBuffer,
            Instruction.symbol(.SetPipe) => .SetPipe,
            else => continue,
        });
    }

    return try instructions.toOwnedSlice(allocator);
}

const Flag = enum {
    Help,
    Symbols,
    Version,
    BufferSize,
    MemorySize,
    CodeExecution,
    TraceMode,

    const Self = @This();

    pub fn short(self: Self) []const u8 {
        return switch (self) {
            .Help => "-h",
            .Symbols => "-s",
            .Version => "-V",
            .BufferSize => "-b",
            .MemorySize => "-m",
            .CodeExecution => "-c",
            .TraceMode => "-t",
        };
    }

    pub fn metavar(self: Self) ?[]const u8 {
        return switch (self) {
            .BufferSize => "size",
            .MemorySize => "memory",
            .CodeExecution => "code",
            else => null,
        };
    }

    pub fn description(self: Self) []const u8 {
        return switch (self) {
            .Help => "prints the usage of the interpereter",
            .Symbols => "prints the code symbols of the interpereter",
            .Version => "prints the version of the interpereter",
            .BufferSize => "sets the io buffer size",
            .MemorySize => "sets the memory size (must be a power of 2)",
            .CodeExecution => "executes the given code",
            .TraceMode => "allows the interpereter to print out each code iteration of the inputted script",
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
    Exit, // exits the program with the exit code being the accumulator value

    DebugDump, // prints a debug trace when crossed

    // adds a number to the accumulator, essentially building the number
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

    AccumulatorZero, // set the accumulator to 0
    AccumulatorSet, // set the accumulator value to the memory value

    InstructionJumpAssign, // assign jump in instruction array
    InstructionZeroJump, // jump to assigned jump in the instruction array when the memory value is 0
    InstructionJump, // jump to assigned jump in the instruction array

    PointerGoto, // go to accumulator value
    PointerRight, // go right by accumulator value
    PointerLeft, // go left by accumulator value

    MemoryAssign, // assign memory to accumulator value
    MemoryIncrement, // increment by accumulator value
    MemoryDecrement, // increment by accumulator value

    // bitwise operations:
    // left side: memory value
    // right side: accumulator value
    BitAnd,
    BitOr,
    BitXor,
    BitShiftLeft,
    BitShiftRight,

    BufferWrite, // push memory value to io buffer
    BufferRead, // pull from io buffer to memory index
    FetchBuffer, // pull from pipe
    FlushBuffer, // flush information to pipe
    SetPipe, // set pipe value to the accumulator value

    const Self = @This();

    pub fn symbol(self: Self) u8 {
        return switch (self) {
            .Exit => '!',
            .DebugDump => '?',
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
            .InstructionJumpAssign => '*',
            .InstructionZeroJump => ';',
            .InstructionJump => ':',
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
            .BufferWrite => '.',
            .BufferRead => ',',
            .FetchBuffer => 'i',
            .FlushBuffer => 'o',
            .SetPipe => '~',
        };
    }

    pub fn description(self: Self) []const u8 {
        return switch (self) {
            .Exit => "exits the program with an exit code from the accumulator",
            .DebugDump => "prints a debug dump of the interpereter state",
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
            .InstructionJumpAssign => "creates a jump point in code that can be used as a goto label",
            .InstructionZeroJump => "jumps to the last assigned jump if the memory value is 0",
            .InstructionJump => "jumps to the last assigned jump",
            .PointerGoto => "sets the memory pointer position to the accumulator value",
            .PointerLeft => "moves the memory pointer position to the left by the accumulator value",
            .PointerRight => "moves the memory pointer position to the right by the accumulator value",
            .MemoryAssign => "sets the current memory value to the accumulator value (max 255)",
            .MemoryIncrement => "increments memory by the accumulator value",
            .MemoryDecrement => "decrements memory by the accumulator value",
            .BitAnd => "bitwise AND",
            .BitOr => "bitwise OR",
            .BitXor => "bitwise XOR",
            .BitShiftLeft => "bitwise left shift",
            .BitShiftRight => "bitwise right shift",
            .BufferWrite => "writes a single byte from memory into the io buffer",
            .BufferRead => "reads a single byte from the io buffer into memory",
            .FetchBuffer => "fetches the next piped buffer from the selected pipe into the io buffer",
            .FlushBuffer => "flushes the io buffer into the selected pipe",
            .SetPipe => "sets the pipe to the accumulator value",
        };
    }
};

pub const Interpereter = struct {
    instructions: []Instruction,
    instruction_ptr: usize = 0,
    instruction_jump_pos: usize = 0,
    accumulator: usize = 0,
    memory: []u8,
    memory_ptr: usize = 0,
    io_buffer: IOBuffer,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, memory_size: usize, instructions: []Instruction, io_buffer: IOBuffer) !Self {
        const memory = try allocator.alloc(u8, memory_size);
        @memset(memory, 0);

        return .{
            .instructions = instructions,
            .memory = memory,
            .io_buffer = io_buffer,
        };
    }

    pub fn deinit(self: *Self, allocator: mem.Allocator) void {
        allocator.free(self.memory);
    }

    pub fn run(self: *Self, writer: *Io.Writer, comptime trace_mode: bool) !u8 {
        while (self.instruction_ptr < self.instructions.len) {
            const instruction = self.instructions[self.instruction_ptr];
            if (trace_mode) {
                try writer.print(
                    "i: {d:<4} | {s:<22} ({c}) | acc: {d:<6} | ptr: {d:<4}\n",
                    .{ self.instruction_ptr, @tagName(instruction), instruction.symbol(), self.accumulator, self.memory_ptr },
                );
            }

            switch (instruction) {
                .Exit => return @truncate(self.accumulator),
                .DebugDump => {
                    // print debug dump
                },
                .Number_0 => self.*.accumulator = (self.accumulator *% 10) +% 0,
                .Number_1 => self.*.accumulator = (self.accumulator *% 10) +% 1,
                .Number_2 => self.*.accumulator = (self.accumulator *% 10) +% 2,
                .Number_3 => self.*.accumulator = (self.accumulator *% 10) +% 3,
                .Number_4 => self.*.accumulator = (self.accumulator *% 10) +% 4,
                .Number_5 => self.*.accumulator = (self.accumulator *% 10) +% 5,
                .Number_6 => self.*.accumulator = (self.accumulator *% 10) +% 6,
                .Number_7 => self.*.accumulator = (self.accumulator *% 10) +% 7,
                .Number_8 => self.*.accumulator = (self.accumulator *% 10) +% 8,
                .Number_9 => self.*.accumulator = (self.accumulator *% 10) +% 9,
                .AccumulatorZero => self.*.accumulator = 0,
                .AccumulatorSet => self.*.accumulator = self.memory[self.memory_ptr],
                .InstructionJumpAssign => self.*.instruction_jump_pos = self.instruction_ptr,
                .InstructionZeroJump => self.*.instruction_ptr = if (self.memory[self.memory_ptr] == 0) self.instruction_jump_pos else self.instruction_ptr,
                .InstructionJump => self.*.instruction_ptr = self.instruction_jump_pos,
                .PointerGoto => self.*.memory_ptr = self.accumulator % self.memory.len,
                .PointerLeft => self.*.memory_ptr = (self.memory_ptr + self.memory.len - (self.accumulator % self.memory.len)) % self.memory.len,
                .PointerRight => self.*.memory_ptr = (self.memory_ptr + self.accumulator) % self.memory.len,
                .MemoryAssign => self.*.memory[self.memory_ptr] = @truncate(self.accumulator),
                .MemoryIncrement => self.*.memory[self.memory_ptr] +%= @truncate(self.accumulator),
                .MemoryDecrement => self.*.memory[self.memory_ptr] -%= @truncate(self.accumulator),
                .BitAnd => self.*.memory[self.memory_ptr] &= @truncate(self.accumulator),
                .BitOr => self.*.memory[self.memory_ptr] |= @truncate(self.accumulator),
                .BitXor => self.*.memory[self.memory_ptr] ^= @truncate(self.accumulator),
                .BitShiftLeft => self.*.memory[self.memory_ptr] <<= @truncate(self.accumulator),
                .BitShiftRight => self.*.memory[self.memory_ptr] >>= @truncate(self.accumulator),
                .BufferWrite => self.*.io_buffer.push(self.memory[self.memory_ptr]),
                .BufferRead => self.*.memory[self.memory_ptr] = self.io_buffer.pull(),
                .FetchBuffer => try self.*.io_buffer.fetch(),
                .FlushBuffer => try self.*.io_buffer.flush(),
                .SetPipe => self.*.io_buffer.fd = @bitCast(@as(u32, @truncate(self.accumulator))),
            }
            self.*.instruction_ptr += 1;
        }

        return 0;
    }
};

pub const IOBuffer = struct {
    fd: i32 = 0,
    index: usize = 0,
    buffer: []u8,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, buffer_size: usize) !Self {
        return .{
            .buffer = try allocator.alloc(u8, buffer_size),
        };
    }

    pub fn deinit(self: *Self, allocator: mem.Allocator) void {
        allocator.free(self.buffer);
    }

    pub fn setFd(self: *Self, fd: i32) void {
        self.*.fd = fd;
    }

    pub fn push(self: *Self, v: u8) void {
        self.*.buffer[@min(self.index, self.buffer.len - 1)] = v;
        self.index += @intFromBool(self.index < self.buffer.len);
    }

    pub fn flush(self: *Self) !void {
        if (self.index == 0) return;
        var written: usize = 0;
        while (written < self.index) {
            const ptr = self.buffer.ptr + written;
            const remaining = self.index - written;

            const rc = os.linux.write(self.fd, ptr, remaining);
            const err = os.linux.errno(rc);

            if (err != .SUCCESS) {
                if (err == .INTR) continue;
                return error.WriteFailed;
            }

            written += rc;
        }

        self.*.index = 0;
    }

    pub fn fetch(self: *Self) !void {
        self.*.index = 0;
        while (true) {
            const rc = os.linux.read(self.fd, self.buffer.ptr, self.buffer.len);
            const err = os.linux.errno(rc);

            if (err != .SUCCESS) {
                if (err == .INTR) continue;
                return error.ReadFailed;
            }

            return;
        }
    }

    pub fn pull(self: *Self) u8 {
        defer self.index += @intFromBool(self.index < self.buffer.len);
        return self.buffer[@min(self.index, self.buffer.len - 1)];
    }
};
