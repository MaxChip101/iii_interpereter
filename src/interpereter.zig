const std = @import("std");
const mem = std.mem;
const os = std.os;
const Io = std.Io;

pub const Memory = struct {
    data: []u8,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, size: usize) !Self {
        const data = try allocator.alloc(u8, size);
        @memset(data, 0);
        return .{
            .data = data,
        };
    }

    pub fn deinit(self: *Self, allocator: mem.Allocator) void {
        allocator.free(self.data);
    }

    pub inline fn read(self: Self, addr: usize) u8 {
        return self.data[addr];
    }

    pub inline fn write(self: *Self, addr: usize, val: u8) void {
        self.*.data[addr] = val;
    }

    pub inline fn bitAnd(self: *Self, addr: usize, mask: u8) void {
        self.*.data[addr] &= mask;
    }

    pub inline fn bitOr(self: *Self, addr: usize, mask: u8) void {
        self.*.data[addr] |= mask;
    }

    pub inline fn bitXor(self: *Self, addr: usize, mask: u8) void {
        self.*.data[addr] ^= mask;
    }

    pub inline fn bitNot(self: *Self, addr: usize) void {
        self.*.data[addr] = ~self.data[addr];
    }

    pub inline fn shiftLeft(self: *Self, addr: usize, shift: u8) void {
        self.data[addr] <<= @as(u3, @truncate(shift & 0x07));
    }

    pub inline fn shiftRight(self: *Self, addr: usize, shift: u8) void {
        self.data[addr] >>= @as(u3, @truncate(shift & 0x07));
    }

    pub inline fn wrapAdd(self: *Self, addr: usize, val: u8) void {
        self.*.data[addr] +%= val;
    }

    pub inline fn wrapSub(self: *Self, addr: usize, val: u8) void {
        self.*.data[addr] -%= val;
    }
};

pub const Interpereter = struct {
    instructions: []Instruction,
    instruction_ptr: usize = 0,
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

    pub fn run(self: *Self) !void {
        _ = self;
        // implement run behavior
    }

    pub fn runDebug(self: *Self, writer: *Io.Writer) !void {
        writer.writeAll("running in debug mode\n");
        _ = self;
        // implement debug run behavior
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
        self.*.buffer[self.index] = v;
        self.index = (self.index + 1) % self.buffer.len;
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

    pub fn fetch(self: *Self) !bool {
        while (true) {
            const rc = os.linux.read(self.fd, self.buffer.ptr, self.buffer.len);
            const err = os.linux.errno(rc);

            if (err != .SUCCESS) {
                if (err == .INTR) continue;
                return error.ReadFailed;
            }

            if (rc == 0) return false; // EOF

            return true;
        }
        self.*.index = 0;
    }

    pub fn pull(self: *Self) u8 {
        defer self.index = (self.index + 1) % self.buffer.len;
        return self.buffer[self.index];
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
    InstructionZeroJump, // jump to assigned jump in the instruction array when memory value is 0
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

    Push, // push memory value to io buffer
    Pull, // pull from io buffer to memory index
    Fetch, // pull from pipe
    Flush, // flush information to pipe
    SetPipe, // set pipe value to the accumulator value
};
