const std = @import("std");
const mem = std.mem;

pub fn Memory(comptime Word: type) type {
    const ShiftType = std.math.log2(Word);

    return struct {
        data: []Word,

        const Self = @This();

        pub fn init(allocator: mem.Allocator, size: usize) !Self {
            const data = try allocator.alloc(Word, size);
            @memset(data, 0);
            return .{
                .data = data,
            };
        }

        pub fn deinit(self: *Self, allocator: mem.Allocator) void {
            allocator.free(self.data);
        }

        pub inline fn read(self: Self, addr: usize) Word {
            return self.data[addr];
        }

        pub inline fn write(self: *Self, addr: usize, val: Word) void {
            self.*.data[addr] = val;
        }

        pub inline fn bitAnd(self: *Self, addr: usize, mask: Word) void {
            self.*.data[addr] &= mask;
        }

        pub inline fn bitOr(self: *Self, addr: usize, mask: Word) void {
            self.*.data[addr] |= mask;
        }

        pub inline fn bitXor(self: *Self, addr: usize, mask: Word) void {
            self.*.data[addr] ^= mask;
        }

        pub inline fn bitNot(self: *Self, addr: usize) void {
            self.*.data[addr] = ~self.data[addr];
        }

        pub inline fn shiftLeft(self: *Self, addr: usize, shift: ShiftType) void {
            self.data[addr] <<= shift;
        }

        pub inline fn shiftRight(self: *Self, addr: usize, shift: ShiftType) void {
            self.data[addr] >>= shift;
        }

        pub inline fn wrapAdd(self: *Self, addr: usize, val: Word) void {
            self.*.data[addr] +%= val;
        }

        pub inline fn wrapSub(self: *Self, addr: usize, val: Word) void {
            self.*.data[addr] -%= val;
        }

        pub fn asBytes(self: *Self) []u8 {
            return mem.sliceAsBytes(self.data);
        }
    };
}

pub const Instruction = enum {};
